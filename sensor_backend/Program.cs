using System.Globalization;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Xml.Linq;
using LibreHardwareMonitor.Hardware;

namespace DeepCool.SensorBackend;

internal static class Program
{
    private const int DefaultPort = 8085;

    public static async Task<int> Main(string[] args)
    {
        var port = ReadPort(args);
        using var monitor = new SensorMonitor();

        try
        {
            monitor.Open();
        }
        catch (Exception error)
        {
            Log.Write(error);
        }

        if (args.Contains("--once", StringComparer.OrdinalIgnoreCase))
        {
            Console.WriteLine(monitor.ReadSnapshotJson());
            return 0;
        }

        var listener = new TcpListener(IPAddress.Loopback, port);
        try
        {
            listener.Start();
        }
        catch (SocketException)
        {
            return 2;
        }

        try
        {
            while (true)
            {
                var client = await listener.AcceptTcpClientAsync();
                _ = Task.Run(() => HandleClientAsync(client, monitor));
            }
        }
        catch (Exception error)
        {
            Log.Write(error);
            return 3;
        }
        finally
        {
            listener.Stop();
        }
    }

    private static int ReadPort(string[] args)
    {
        for (var index = 0; index < args.Length - 1; index++)
        {
            if (args[index].Equals("--port", StringComparison.OrdinalIgnoreCase) &&
                int.TryParse(args[index + 1], NumberStyles.None, CultureInfo.InvariantCulture, out var port) &&
                port is > 0 and <= 65535)
            {
                return port;
            }
        }

        return DefaultPort;
    }

    private static async Task HandleClientAsync(TcpClient client, SensorMonitor monitor)
    {
        try
        {
            using (client)
            using (var stream = client.GetStream())
            {
                var buffer = new byte[2048];
                var read = await stream.ReadAsync(buffer, 0, buffer.Length);
                var request = Encoding.ASCII.GetString(buffer, 0, read);
                var path = request
                    .Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries)
                    .Skip(1)
                    .FirstOrDefault() ?? "/";
                var body = path.StartsWith("/health", StringComparison.OrdinalIgnoreCase)
                    ? "{\"ok\":true}"
                    : monitor.ReadSnapshotJson();
                var bodyBytes = Encoding.UTF8.GetBytes(body);
                var header = Encoding.ASCII.GetBytes(
                    "HTTP/1.1 200 OK\r\n" +
                    "Content-Type: application/json; charset=utf-8\r\n" +
                    "Cache-Control: no-cache\r\n" +
                    $"Content-Length: {bodyBytes.Length}\r\n" +
                    "Connection: close\r\n\r\n");
                await stream.WriteAsync(header, 0, header.Length);
                await stream.WriteAsync(bodyBytes, 0, bodyBytes.Length);
            }
        }
        catch
        {
            // The Dart side polls again every few seconds.
        }
    }
}

internal sealed class SensorMonitor : IDisposable
{
    private readonly object _gate = new();
    private readonly Computer _computer;
    private bool _opened;

    public SensorMonitor()
    {
        _computer = new Computer(ConfigSettings.Load())
        {
            IsCpuEnabled = true,
            IsGpuEnabled = true,
            IsMemoryEnabled = true,
            IsMotherboardEnabled = true,
            IsStorageEnabled = true,
            IsControllerEnabled = true,
            IsNetworkEnabled = false,
            IsPsuEnabled = true,
        };
    }

    public void Open()
    {
        lock (_gate)
        {
            if (_opened)
            {
                return;
            }

            _computer.Open();
            _opened = true;
        }
    }

    public string ReadSnapshotJson()
    {
        lock (_gate)
        {
            try
            {
                if (!_opened)
                {
                    Open();
                }

                var sensors = new List<SensorReading>();
                foreach (var hardware in _computer.Hardware)
                {
                    ReadHardware(hardware, sensors);
                }

                return Json.BuildSnapshot(true, null, sensors);
            }
            catch (Exception error)
            {
                Log.Write(error);
                return Json.BuildSnapshot(false, error.Message, Array.Empty<SensorReading>());
            }
        }
    }

    private static void ReadHardware(IHardware hardware, List<SensorReading> sensors)
    {
        try
        {
            hardware.Update();
        }
        catch (Exception error)
        {
            Log.Write(error);
        }

        foreach (var subHardware in hardware.SubHardware ?? Array.Empty<IHardware>())
        {
            ReadHardware(subHardware, sensors);
        }

        foreach (var sensor in hardware.Sensors ?? Array.Empty<ISensor>())
        {
            if (sensor?.Value is not { } value)
            {
                continue;
            }

            sensors.Add(
                new SensorReading(
                    sensor.Name ?? string.Empty,
                    sensor.SensorType.ToString(),
                    sensor.Identifier?.ToString() ?? string.Empty,
                    value,
                    hardware.Name ?? string.Empty,
                    hardware.HardwareType.ToString()));
        }
    }

    public void Dispose()
    {
        lock (_gate)
        {
            if (_opened)
            {
                _computer.Close();
                _opened = false;
            }
        }
    }
}

internal sealed class SensorReading
{
    public SensorReading(
        string name,
        string type,
        string identifier,
        float value,
        string hardware,
        string hardwareType)
    {
        Name = name;
        Type = type;
        Identifier = identifier;
        Value = value;
        Hardware = hardware;
        HardwareType = hardwareType;
    }

    public string Name { get; }
    public string Type { get; }
    public string Identifier { get; }
    public float Value { get; }
    public string Hardware { get; }
    public string HardwareType { get; }
}

internal static class Json
{
    public static string BuildSnapshot(
        bool available,
        string? error,
        IReadOnlyList<SensorReading> sensors)
    {
        var builder = new StringBuilder();
        builder.Append("{\"available\":");
        builder.Append(available ? "true" : "false");
        builder.Append(",\"error\":");
        AppendString(builder, error);
        builder.Append(",\"sensors\":[");

        for (var index = 0; index < sensors.Count; index++)
        {
            if (index > 0)
            {
                builder.Append(',');
            }

            var sensor = sensors[index];
            builder.Append('{');
            AppendProperty(builder, "name", sensor.Name);
            builder.Append(',');
            AppendProperty(builder, "type", sensor.Type);
            builder.Append(',');
            AppendProperty(builder, "identifier", sensor.Identifier);
            builder.Append(",\"value\":");
            builder.Append(sensor.Value.ToString("0.###", CultureInfo.InvariantCulture));
            builder.Append(',');
            AppendProperty(builder, "hardware", sensor.Hardware);
            builder.Append(',');
            AppendProperty(builder, "hardwareType", sensor.HardwareType);
            builder.Append('}');
        }

        builder.Append("]}");
        return builder.ToString();
    }

    private static void AppendProperty(StringBuilder builder, string name, string? value)
    {
        AppendString(builder, name);
        builder.Append(':');
        AppendString(builder, value);
    }

    private static void AppendString(StringBuilder builder, string? value)
    {
        if (value is null)
        {
            builder.Append("null");
            return;
        }

        builder.Append('"');
        foreach (var character in value)
        {
            switch (character)
            {
                case '\\':
                    builder.Append("\\\\");
                    break;
                case '"':
                    builder.Append("\\\"");
                    break;
                case '\r':
                    builder.Append("\\r");
                    break;
                case '\n':
                    builder.Append("\\n");
                    break;
                case '\t':
                    builder.Append("\\t");
                    break;
                default:
                    if (char.IsControl(character))
                    {
                        builder.Append("\\u");
                        builder.Append(((int)character).ToString("x4", CultureInfo.InvariantCulture));
                    }
                    else
                    {
                        builder.Append(character);
                    }

                    break;
            }
        }

        builder.Append('"');
    }
}

internal sealed class ConfigSettings : ISettings
{
    private readonly Dictionary<string, string> _values;

    private ConfigSettings(Dictionary<string, string> values)
    {
        _values = values;
    }

    public static ConfigSettings Load()
    {
        var values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var path = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "LibreHardwareMonitor.config");
        if (!File.Exists(path))
        {
            return new ConfigSettings(values);
        }

        try
        {
            var document = XDocument.Load(path);
            foreach (var node in document.Descendants("add"))
            {
                var key = node.Attribute("key")?.Value;
                var value = node.Attribute("value")?.Value;
                if (!string.IsNullOrEmpty(key) && value != null)
                {
                    values[key!] = value;
                }
            }
        }
        catch (Exception error)
        {
            Log.Write(error);
        }

        return new ConfigSettings(values);
    }

    public bool Contains(string name) => _values.ContainsKey(name);

    public void SetValue(string name, string value)
    {
        _values[name] = value;
    }

    public string GetValue(string name, string value)
    {
        return _values.TryGetValue(name, out var found) ? found : value;
    }

    public void Remove(string name)
    {
        _values.Remove(name);
    }
}

internal static class Log
{
    public static void Write(Exception error)
    {
        try
        {
            var path = Path.Combine(Path.GetTempPath(), "deepcool-sensor-backend.log");
            File.AppendAllText(
                path,
                DateTime.Now.ToString("O", CultureInfo.InvariantCulture) +
                " " +
                error +
                Environment.NewLine);
        }
        catch
        {
            // Logging must never break sensor reads.
        }
    }
}

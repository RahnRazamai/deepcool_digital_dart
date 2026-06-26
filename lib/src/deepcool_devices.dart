import 'ch170_display.dart';
import 'hidapi.dart';

const int ch510VendorId = 0x34d3;
const int ch510ProductId = 0x1100;

enum DeepCoolDeviceFamily {
  agSeries,
  akSeries,
  ak400Pro,
  ak620Pro,
  chSeries,
  chSeriesGen2,
  ch510,
  ldSeries,
  lpSeries,
  lqSeries,
  lsSeries,
}

final class DeepCoolDeviceDefinition {
  const DeepCoolDeviceDefinition({
    required this.vendorId,
    required this.productId,
    required this.name,
    required this.family,
  });

  final int vendorId;
  final int productId;
  final String name;
  final DeepCoolDeviceFamily family;
}

final class DeepCoolDeviceTarget {
  const DeepCoolDeviceTarget(this.definition, {this.deviceInfo});

  final DeepCoolDeviceDefinition definition;
  final HidDeviceInfo? deviceInfo;

  int get vendorId => definition.vendorId;
  int get productId => definition.productId;
  String get name {
    final product = deviceInfo?.product.trim();
    return product == null || product.isEmpty ? definition.name : product;
  }

  DeepCoolDeviceFamily get family => definition.family;
}

const List<DeepCoolDeviceDefinition> supportedDeepCoolDevices = [
  DeepCoolDeviceDefinition(
    vendorId: deepCoolVendorId,
    productId: 1,
    name: 'AK400 DIGITAL',
    family: DeepCoolDeviceFamily.akSeries,
  ),
  DeepCoolDeviceDefinition(
    vendorId: deepCoolVendorId,
    productId: 2,
    name: 'AK620 DIGITAL',
    family: DeepCoolDeviceFamily.akSeries,
  ),
  DeepCoolDeviceDefinition(
    vendorId: deepCoolVendorId,
    productId: 3,
    name: 'AK500 DIGITAL',
    family: DeepCoolDeviceFamily.akSeries,
  ),
  DeepCoolDeviceDefinition(
    vendorId: deepCoolVendorId,
    productId: 4,
    name: 'AK500S DIGITAL',
    family: DeepCoolDeviceFamily.akSeries,
  ),
  DeepCoolDeviceDefinition(
    vendorId: deepCoolVendorId,
    productId: 5,
    name: 'CH560 DIGITAL',
    family: DeepCoolDeviceFamily.chSeries,
  ),
  DeepCoolDeviceDefinition(
    vendorId: deepCoolVendorId,
    productId: 6,
    name: 'LS520/LS720 SE DIGITAL',
    family: DeepCoolDeviceFamily.lsSeries,
  ),
  DeepCoolDeviceDefinition(
    vendorId: deepCoolVendorId,
    productId: 7,
    name: 'MORPHEUS',
    family: DeepCoolDeviceFamily.chSeries,
  ),
  DeepCoolDeviceDefinition(
    vendorId: deepCoolVendorId,
    productId: 8,
    name: 'AG300/AG400/AG500/AG620 DIGITAL',
    family: DeepCoolDeviceFamily.agSeries,
  ),
  DeepCoolDeviceDefinition(
    vendorId: deepCoolVendorId,
    productId: 10,
    name: 'LD240/LD360',
    family: DeepCoolDeviceFamily.ldSeries,
  ),
  DeepCoolDeviceDefinition(
    vendorId: deepCoolVendorId,
    productId: 12,
    name: 'LP240/LP360',
    family: DeepCoolDeviceFamily.lpSeries,
  ),
  DeepCoolDeviceDefinition(
    vendorId: deepCoolVendorId,
    productId: 13,
    name: 'LQ240/LQ360',
    family: DeepCoolDeviceFamily.lqSeries,
  ),
  DeepCoolDeviceDefinition(
    vendorId: deepCoolVendorId,
    productId: 15,
    name: 'ASSASSIN IV VC VISION',
    family: DeepCoolDeviceFamily.lqSeries,
  ),
  DeepCoolDeviceDefinition(
    vendorId: deepCoolVendorId,
    productId: 16,
    name: 'AK400 DIGITAL PRO',
    family: DeepCoolDeviceFamily.ak400Pro,
  ),
  DeepCoolDeviceDefinition(
    vendorId: deepCoolVendorId,
    productId: 17,
    name: 'AK500 DIGITAL PRO',
    family: DeepCoolDeviceFamily.ak620Pro,
  ),
  DeepCoolDeviceDefinition(
    vendorId: deepCoolVendorId,
    productId: 18,
    name: 'AK620 DIGITAL PRO',
    family: DeepCoolDeviceFamily.ak620Pro,
  ),
  DeepCoolDeviceDefinition(
    vendorId: deepCoolVendorId,
    productId: ch170ProductId,
    name: 'CH170 DIGITAL',
    family: DeepCoolDeviceFamily.chSeriesGen2,
  ),
  DeepCoolDeviceDefinition(
    vendorId: deepCoolVendorId,
    productId: 21,
    name: 'CH360 DIGITAL',
    family: DeepCoolDeviceFamily.chSeries,
  ),
  DeepCoolDeviceDefinition(
    vendorId: deepCoolVendorId,
    productId: ch270ProductId,
    name: 'CH270 DIGITAL',
    family: DeepCoolDeviceFamily.chSeriesGen2,
  ),
  DeepCoolDeviceDefinition(
    vendorId: deepCoolVendorId,
    productId: ch690ProductId,
    name: 'CH690 DIGITAL',
    family: DeepCoolDeviceFamily.chSeriesGen2,
  ),
  DeepCoolDeviceDefinition(
    vendorId: deepCoolVendorId,
    productId: 31,
    name: 'ASSASSIN IV VC VISION',
    family: DeepCoolDeviceFamily.lqSeries,
  ),
  DeepCoolDeviceDefinition(
    vendorId: deepCoolVendorId,
    productId: 41,
    name: 'AK620 G2 DIGITAL NYX',
    family: DeepCoolDeviceFamily.lqSeries,
  ),
  DeepCoolDeviceDefinition(
    vendorId: deepCoolVendorId,
    productId: 42,
    name: 'AK700 DIGITAL NYX',
    family: DeepCoolDeviceFamily.lqSeries,
  ),
  DeepCoolDeviceDefinition(
    vendorId: deepCoolVendorId,
    productId: 43,
    name: 'AK400 G2 DIGITAL NYX',
    family: DeepCoolDeviceFamily.lqSeries,
  ),
  DeepCoolDeviceDefinition(
    vendorId: deepCoolVendorId,
    productId: 44,
    name: 'AK500 G2 DIGITAL NYX',
    family: DeepCoolDeviceFamily.lqSeries,
  ),
  DeepCoolDeviceDefinition(
    vendorId: ch510VendorId,
    productId: ch510ProductId,
    name: 'CH510 MESH DIGITAL',
    family: DeepCoolDeviceFamily.ch510,
  ),
];

DeepCoolDeviceDefinition? deepCoolDeviceDefinitionFor({
  required int vendorId,
  required int productId,
}) {
  for (final definition in supportedDeepCoolDevices) {
    if (definition.vendorId == vendorId && definition.productId == productId) {
      return definition;
    }
  }
  return null;
}

DeepCoolDeviceDefinition? deepCoolDeviceDefinitionForProductId(int productId) {
  for (final definition in supportedDeepCoolDevices) {
    if (definition.productId == productId) {
      return definition;
    }
  }
  return null;
}

String deepCoolProductName(int productId, {int vendorId = deepCoolVendorId}) {
  return deepCoolDeviceDefinitionFor(
        vendorId: vendorId,
        productId: productId,
      )?.name ??
      'DeepCool VID 0x${vendorId.toRadixString(16)} PID $productId';
}

String supportedDeepCoolProductNames() {
  return supportedDeepCoolDevices.map((device) => device.name).join(', ');
}

DeepCoolDeviceTarget? findSupportedDeepCoolDisplay(
  HidApi api, {
  int productId = 0,
}) {
  final devices = enumerateSupportedDeepCoolDisplays(api);
  for (final target in devices) {
    if (productId == 0 || target.productId == productId) {
      return target;
    }
  }
  return null;
}

List<DeepCoolDeviceTarget> enumerateSupportedDeepCoolDisplays(HidApi api) {
  final targets = <DeepCoolDeviceTarget>[];
  final hidDevices = [
    ...api.enumerate(vendorId: deepCoolVendorId),
    ...api.enumerate(vendorId: ch510VendorId),
  ];

  for (final device in hidDevices) {
    final definition = deepCoolDeviceDefinitionFor(
      vendorId: device.vendorId,
      productId: device.productId,
    );
    if (definition != null) {
      targets.add(DeepCoolDeviceTarget(definition, deviceInfo: device));
    }
  }
  return targets;
}

bool isSupportedDeepCoolDevice({
  required int vendorId,
  required int productId,
}) {
  return deepCoolDeviceDefinitionFor(
        vendorId: vendorId,
        productId: productId,
      ) !=
      null;
}

library toolchain.dart.boilerplate.http_apis.generate.script;

import 'dart:io';

import 'package:http_apis_define/http_apis.dart';

/// 1. Define the API class using the http_apis_define package
/// 2. Copy+paste the definition into the global [api] variable below
/// 3. Replace all `handleRequest` declarations with [emptyHandler]
/// 4. Run the script
/// 5. Copy+paste the file(s) from the lib/output folder into your client-side package
Future<int> emptyHandler(
        {required T? Function<T>(String) getParam,
        required void Function(int, String) raise}) async =>
    0;
late final API api = API(
  apiName: 'users_api',
  routes: [
    RouteSegment.routes(
      routeName: 'account',
      routes: [
        RouteSegment.endpoint(
          routeName: 'create',
          endpoint: Endpoint(
            endpointTypes: [EndpointType.post],
            requiresAuth: true,
            queryParameters: const [],
            bodyParameters: null,
            handleRequest: emptyHandler,
          ),
        ),
      ],
    ),
  ],
);
void main(List<String> args) async {
  final String intermediateClientName = api.apiName.split('_').join();
  final String clientName =
      '${intermediateClientName[0].toUpperCase()}${intermediateClientName.substring(1)}';
  final StringBuffer generated = StringBuffer("""import 'dart:convert';
import 'package:http/http.dart' as http;

class $clientName {
  static const String apiName = '${api.apiName}';
  static const String apiHost = 'apis.obsivision.com';

""");
  final StringBuffer classDefinitions = StringBuffer();
  final (List<Endpoint>, List<String>) endpointsAndRoutes =
      traverseRoutes(api.routes, '/${api.apiName.split('_')[0]}');
  if (endpointsAndRoutes.$1.isNotEmpty) {
    for (int i = 0; i < endpointsAndRoutes.$1.length; i++) {
      final Endpoint endpoint = endpointsAndRoutes.$1[i];
      final String routePath = endpointsAndRoutes.$2[i].substring(1);
      final String intermediateName = routePath
          .split(RegExp(r'[/-]'))
          .map((route) => '${route[0].toUpperCase()}${route.substring(1)}')
          .join();
      final String endpointName =
          '${intermediateName[0].toLowerCase()}${intermediateName.substring(1)}';
      final String className = '${intermediateName}Endpoint';
      generated.writeln("  static final $endpointName = $className();");
      classDefinitions.writeln("class $className {");
      final String qParams = [
        for (final qparam in endpoint.queryParameters)
          "${qparam.encodedType} ${qparam.name},"
      ].join('\n');
      for (final endpointType in endpoint.endpointTypes) {
        classDefinitions.writeln(
            '  Future<http.Response> ${endpointType.method.toLowerCase()}(');
        if (qParams.isNotEmpty || endpoint.bodyParameters != null) {
          classDefinitions.write('{');
        }
        if (qParams.isNotEmpty) {
          classDefinitions.write("""
    required ({
      $qParams
    }) queryParameters,
    """);
        }
        if (![EndpointType.delete, EndpointType.get].contains(endpointType) &&
            endpoint.bodyParameters != null) {
          final String bParams = [
            for (final bparam in endpoint.bodyParameters!)
              "${bparam.encodedType} ${bparam.name},"
          ].join('\n');
          classDefinitions.write("""
required ({
      $bParams
    }) bodyParameters,
  
""");
        }
        if (qParams.isNotEmpty || endpoint.bodyParameters != null) {
          classDefinitions.write('}');
        }
        final String? qParamsString;
        if (qParams.isNotEmpty || endpoint.bodyParameters != null) {
          qParamsString = """{
          ${[
            for (final qparam in endpoint.queryParameters)
              "'${qparam.name}': queryParameters.${qparam.name},",
          ].join('\n')}
        }""";
        } else {
          qParamsString = null;
        }
        classDefinitions.write(""") async {
    return await http.${endpointType.method.toLowerCase()}(
      Uri.https(
        'apis.obsivision.com',
        '$routePath',
        $qParamsString,
      ),
    """);
        if (![EndpointType.delete, EndpointType.get].contains(endpointType) &&
            endpoint.bodyParameters != null) {
          classDefinitions.write("""
body: jsonEncode({
  
          ${[
            for (final bparam in endpoint.bodyParameters!)
              "'${bparam.name}': bodyParameters.${bparam.name},",
          ].join('\n')}
}),
""");
        }
        classDefinitions.writeln(");\n}\n}");
      }
    }
  }
  generated
    ..writeln("}")
    ..write(classDefinitions.toString());

  await (await File('./lib/output/${api.apiName}_client.g.dart').create())
      .writeAsString(generated.toString());
}

(List<Endpoint>, List<String>) traverseRoutes(
    List<RouteSegment> routes, String parent) {
  if (routes.isEmpty) return const ([], []);
  final (List<Endpoint>, List<String>) results = ([], []);
  for (final route in routes) {
    if (route.endpoint == null) {
      final tmp = traverseRoutes(route.routes!, '$parent/${route.routeName}');
      results
        ..$1.addAll(tmp.$1)
        ..$2.addAll(tmp.$2);
    } else {
      results
        ..$1.add(route.endpoint!)
        ..$2.add('$parent/${route.routeName}');
    }
  }
  return results;
}

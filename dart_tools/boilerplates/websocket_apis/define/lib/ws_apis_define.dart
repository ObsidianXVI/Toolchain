library toolchain.dart.boilerplate.ws_apis_define;

import 'dart:io';
import 'dart:typed_data';

String _getPathSeg(Map<String, Object?> request, [int pathSegmentOffset = 0]) =>
    (request['endpoint'] as String).split('/')[pathSegmentOffset];

class API {
  final String apiName;
  final List<RouteSegment> routes;
  BinaryEndpoint? lastRequestedEndpoint;

  API({
    required this.apiName,
    required this.routes,
  });

  /// Handles the given HTTP [request] by routing it to the appropriate endpoint. If the actual
  /// route doesn't start from the first path segment, specify the appropriate [pathSegmentOffset] accordingly.
  /// For example:
  /// ```dart
  /// 'https://domain.com/resources/get/ID'            // pathSegmentOffset should be 0
  /// 'https://domain.com/some_api/resources/get/ID'   // pathSegmentOffset should be 1
  /// ```
  Future<Map<String, Object?>> handleRequest(
    Object? request, {
    int pathSegmentOffset = 0,
  }) async {
    final Map<String, Object?> response = {};
    bool isValid = false;
    if (request is Map) {
      final casted = request.cast<String, Object?>();

      for (final route in routes) {
        if (route.routeName == _getPathSeg(casted, pathSegmentOffset)) {
          isValid = true;
          return await route.handleRequestToRoute(
            casted,
            response,
            pathSegmentOffset,
            preflight: request.containsKey('O-Preflight'),
          );
        }
      }
      response['statusCode'] = HttpStatus.notFound;
      response.addAll({
        "msg":
            "The requested route segment '${_getPathSeg(casted, pathSegmentOffset)}' does not exist.",
      });
      return response;
    } else if (request is Uint8List) {
      if (lastRequestedEndpoint != null) {
        final res = await lastRequestedEndpoint!
            .handleRequestToEndpoint(request, response);
        lastRequestedEndpoint = null;
        return res;
      } else {
        response['statusCode'] = HttpStatus.conflict;
        response.addAll({
          "msg": "The binary message sent was not preflighted.",
        });
      }
    }

    if (!isValid) {
      response['statusCode'] = HttpStatus.badRequest;
      response.addAll({
        "msg":
            "The message is of unknown type, or an unknown error occurred when being parsed by the API.",
      });
    }
    return response;
  }
}

class RouteSegment {
  final String routeName;
  final List<RouteSegment>? routes;
  final Endpoint? endpoint;

  const RouteSegment.endpoint({
    required this.routeName,
    required Endpoint this.endpoint,
  }) : routes = null;

  const RouteSegment.routes({
    required this.routeName,
    required List<RouteSegment> this.routes,
  }) : endpoint = null;

  bool get isEndpoint => endpoint != null;

  Future<Map<String, Object?>> handleRequestToRoute(
    Map<String, Object?> request,
    Map<String, Object?> response,
    int routeSegIndex, {
    bool preflight = false,
  }) async {
    if (isEndpoint) {
      return await endpoint!.handleRequestToEndpoint(
        request,
        response,
        preflight: preflight,
      );
    } else {
      bool isValid = false;
      for (final route in routes!) {
        if (route.routeName == _getPathSeg(request, routeSegIndex + 1)) {
          isValid = true;
          return await route.handleRequestToRoute(
            request,
            response,
            routeSegIndex + 1,
            preflight: preflight,
          );
        }
      }

      if (!isValid) {
        response['statusCode'] = HttpStatus.notFound;
        response.addAll({
          "msg":
              "The requested route segment '${_getPathSeg(request, routeSegIndex + 1)}' does not exist.",
        });
      }
      return response;
    }
  }
}

sealed class Endpoint<T> {
  final Future<int> Function({
    required T? Function<T>(String paramName) getParam,
    required int Function(int statusCode, String issue) raise,
    required void Function(Map<String, Object?> body) writeBody,
  }) handleRequest;
  const Endpoint({
    required this.handleRequest,
  });

  Future<Map<String, Object?>> handleRequestToEndpoint(
    T request,
    Map<String, Object?> response, {
    bool preflight = false,
  });
}

class BinaryEndpoint extends Endpoint<Uint8List> {
  const BinaryEndpoint({
    required super.handleRequest,
  });

  void handlePreflightRequest(Map<String, Object?> request) {}

  @override
  Future<Map<String, Object?>> handleRequestToEndpoint(
      Uint8List request, Map<String, Object?> response,
      {bool preflight = false}) async {
    T? getParam<T>(String _) => null;
    void writeBody(Map<String, Object?> _) {}

    response['statusCode'] = await handleRequest(
      getParam: getParam,
      writeBody: writeBody,
      raise: (statusCode, issue) {
        response.addAll({'msg': issue});
        return statusCode;
      },
    );
    throw UnimplementedError();
  }
}

class JSONEndpoint extends Endpoint<Map<String, Object?>> {
  final List<Param> params;

  const JSONEndpoint({
    required this.params,
    required super.handleRequest,
  });

  @override
  Future<Map<String, Object?>> handleRequestToEndpoint(
    Map<String, Object?> request,
    Map<String, Object?> response, {
    bool preflight = false,
  }) async {
    // Check for request method validity (if request body is expected, it should be provided,
    // and PATCH/OPTIONS requests are automatically handled)
    Map<String, Object?> payload;
    if (params.isNotEmpty) {
      if (request.keys.isNotEmpty) {
        payload = request;
      } else {
        print(
            "This endpoint expects a valid argument body, but an empty body was provided.");
        request['statusCode'] = HttpStatus.badRequest;
        request.addAll({
          'msg':
              "This endpoint expects a valid argument body, but an empty body was provided.",
        });
        return response;
      }
    } else {
      payload = const {};
    }

    bool isValidReq = true;
    final List<String> issues = [];
    final Map<String, dynamic> paramStore = {};

    for (final param in params) {
      paramStore[param.name] = param.getFromPayload(
        payload,
        payloadSource: 'params',
        ifInvalid: (issue) {
          issues.add(issue);
          isValidReq = false;
        },
      );
    }

    if (!isValidReq) {
      print(
          "Malformed parameters (either missing or invalid types) in query/body.");
      response['statusCode'] = HttpStatus.badRequest;
      response.addAll({
        "msg":
            "Malformed parameters (either missing or invalid types) in query/body.",
        "issues": issues,
      });
      return response;
    } else {
      T? getParam<T>(String paramName) => paramStore[paramName] as T;
      void writeBody(Map<String, Object?> body) => response.addAll(body);
      response['statusCode'] = await handleRequest(
        getParam: getParam,
        writeBody: writeBody,
        raise: (statusCode, issue) {
          response.addAll({'msg': issue});
          return statusCode;
        },
      );

      return response;
    }
  }
}

class Param<T, C> {
  final String name;
  final bool required;
  final String desc;
  final T Function(Object?) cast;

  const Param.required(
    this.name, {
    required this.desc,
    required this.cast,
  }) : required = true;
  const Param.optional(
    this.name, {
    required this.desc,
    required this.cast,
  }) : required = false;

  String get nativeType => T.toString();
  String get encodedType => C.toString();

  T? getFromPayload(
    Map<String, Object?> payload, {
    required String payloadSource,
    required void Function(String) ifInvalid,
  }) {
    if (required && payload.containsKey(name)) {
      try {
        return cast(payload[name]);
      } catch (_, __) {
        ifInvalid(
            "Invalid param '$name' in $payloadSource: Typecast from '$C' to '$T' failed.");
      }
    } else {
      ifInvalid(
          "Missing required param '$name' in $payloadSource: Value of type '$C' (castable to '$T') must be provided.");
    }
    return null;
  }
}

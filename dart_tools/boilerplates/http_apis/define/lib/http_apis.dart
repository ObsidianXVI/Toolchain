library toolchain.dart.boilerplate.http_apis.define;

import 'package:http_apis_secure/secure.dart' as secure;
import 'dart:convert';
import 'dart:io';

enum AuthModel {
  hellcat,
  classic_sym,
  // classic_jwt,
}

enum HellcatHeaders {
  email('H-email'),
  verified('H-verified'),
  uid('H-uid'),
  claims('H-claims'),
  authorization('H-authorization');

  final String header;

  const HellcatHeaders(this.header);
}

enum ClassicSymParams {
  uid('uid'),
  iv('iv'),
  cipher('cipher');

  final String name;
  const ClassicSymParams(this.name);
}

class API {
  final String apiName;
  final List<RouteSegment> routes;

  const API({
    required this.apiName,
    required this.routes,
  });

  /// Handles the given [request] by routing it to the appropriate endpoint. If the actual
  /// route doesn't start from the first path segment, specify the appropriate [pathSegmentOffset] accordingly.
  /// For example:
  /// ```dart
  /// 'https://domain.com/resources/get/ID'            // pathSegmentOffset should be 0
  /// 'https://domain.com/some_api/resources/get/ID'   // pathSegmentOffset should be 1
  /// ```
  Future<void> handleRequest(
    HttpRequest request, {
    int pathSegmentOffset = 0,
  }) async {
    bool isValid = false;
    request.response.headers.set('Content-Type', 'application/json');
    for (final route in routes) {
      if (route.routeName == request.uri.pathSegments[pathSegmentOffset]) {
        isValid = true;
        await route.handleRequestToRoute(request, pathSegmentOffset);
        break;
      }
    }

    if (!isValid) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write(jsonEncode({
          "msg":
              "The requested route segment '${request.uri.pathSegments[0]}' does not exist.",
        }));
    }
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

  Future<void> handleRequestToRoute(
      HttpRequest request, int routeSegIndex) async {
    if (isEndpoint) {
      await endpoint!.handleRequestToEndpoint(request);
    } else {
      bool isValid = false;
      for (final route in routes!) {
        if (route.routeName == request.uri.pathSegments[routeSegIndex + 1]) {
          isValid = true;
          await route.handleRequestToRoute(request, routeSegIndex + 1);
          break;
        }
      }

      if (!isValid) {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write(jsonEncode({
            "msg":
                "The requested route segment '${request.uri.pathSegments[routeSegIndex + 1]}' does not exist.",
          }));
        return;
      }
    }
  }
}

enum EndpointType {
  get('GET'),
  post('POST'),
  patch('PATCH'),
  options('OPTIONS'),
  ;

  final String method;
  const EndpointType(this.method);
}

base class Endpoint {
  final List<EndpointType> endpointTypes;
  final List<Param> queryParameters;
  final List<Param>? bodyParameters;
  final bool requiresAuth;
  final AuthModel authModel;
  final Future<int> Function({
    required T? Function<T>(String paramName) getParam,
    required int Function(int statusCode, String issue) raise,
    required void Function(String body) writeBody,
  }) handleRequest;

  const Endpoint({
    required this.endpointTypes,
    required this.queryParameters,
    required this.bodyParameters,
    required this.handleRequest,
    required this.requiresAuth,
    required this.authModel,
  });

  Future<void> handleRequestToEndpoint(HttpRequest request) async {
    // Check for request method validity (if request body is expected, it should be provided,
    // and PATCH/OPTIONS requests are automatically handled)
    Map<String, Object?> payload;
    if (endpointTypes.map((t) => t.method).contains(request.method)) {
      if (bodyParameters != null) {
        try {
          payload = jsonDecode(await utf8.decodeStream(request));
        } catch (e, __) {
          print(
              "This endpoint expects a valid request body, but an error occurred when parsing it.");
          request.response
            ..statusCode = HttpStatus.badRequest
            ..write(jsonEncode({
              'msg':
                  "This endpoint expects a valid request body, but an error occurred when parsing it.",
              'error': e,
            }));
          return;
        }
      } else {
        payload = const {};
      }
    } else if (endpointTypes.any((type) => [
              EndpointType.patch,
              EndpointType.options,
            ].contains(type)) &&
        request.method == EndpointType.options.method) {
      // Handle preflight requests
      request.response.statusCode = HttpStatus.ok;
      return;
    } else {
      request.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..write(jsonEncode({
          'msg':
              "This endpoint only supports ${endpointTypes.map((t) => t.method).join(', ')} but the request's method is ${request.method}."
        }));
      return;
    }

    if (requiresAuth) {
      switch (authModel) {
        case AuthModel.hellcat:
          if (request.headers.value(HellcatHeaders.authorization.header) ==
              null) {
            print(
                "This endpoint requires an Authorization header to be passed in the 'Bearer <TOKEN>' format, but said header is missing.");
            request.response
              ..statusCode = HttpStatus.unauthorized
              ..write(jsonEncode({
                'msg':
                    "This endpoint requires an Authorization header to be passed in the 'Bearer <TOKEN>' format, but said header is missing."
              }));
          }
          return;
        case AuthModel.classic_sym:
          break;
      }
    }

    bool isValidReq = true;
    final List<String> issues = [];
    final Map<String, dynamic> paramStore = switch (authModel) {
      AuthModel.hellcat => {
          HellcatHeaders.authorization.header:
              request.headers.value(HellcatHeaders.authorization.header) ??
                  (throw Exception('what')),
          HellcatHeaders.email.header:
              request.headers.value(HellcatHeaders.email.header),
          HellcatHeaders.uid.header:
              request.headers.value(HellcatHeaders.uid.header),
          HellcatHeaders.verified.header:
              request.headers.value(HellcatHeaders.verified.header),
          if (request.headers.value(HellcatHeaders.claims.header) != null)
            HellcatHeaders.claims.header: jsonDecode(
                request.headers.value(HellcatHeaders.claims.header)!),
        },
      AuthModel.classic_sym => {
          ClassicSymParams.uid.name:
              request.headers.value(ClassicSymParams.uid.name),
          ClassicSymParams.iv.name: payload[ClassicSymParams.iv.name]!,
          ClassicSymParams.cipher.name: payload[ClassicSymParams.cipher.name]!,
        },
    };

    // Only the Classic Symmetric model will pass all params through the body, and
    // not through query params (since the body is encrypted).
    if (authModel != AuthModel.classic_sym) {
      for (final param in queryParameters) {
        paramStore[param.name] = param.getFromPayload(
          request.uri.queryParameters,
          payloadSource: 'query params',
          ifInvalid: (issue) {
            issues.add(issue);
            isValidReq = false;
          },
        );
      }
    }

    if (bodyParameters != null) {
      for (final param in bodyParameters!) {
        paramStore[param.name] = param.getFromPayload(
          payload,
          payloadSource: 'body params',
          ifInvalid: (issue) {
            issues.add(issue);
            isValidReq = false;
          },
        );
      }
    }

    if (!isValidReq) {
      print(
          "Malformed parameters (either missing or invalid types) in query/body.");
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write(jsonEncode({
          "msg":
              "Malformed parameters (either missing or invalid types) in query/body.",
          "issues": issues,
        }));
      return;
    } else {
      final StringBuffer responseBody = StringBuffer();
      T? getParam<T>(String paramName) => paramStore[paramName] as T;
      void writeBody(String body) => responseBody.write(body);
      request.response.statusCode = await handleRequest(
        getParam: getParam,
        writeBody: writeBody,
        raise: (statusCode, issue) {
          request.response.statusCode = statusCode;
          responseBody.write(jsonEncode({'msg': issue}));
          return statusCode;
        },
      );
      request.response.write(responseBody.toString());
      return;
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

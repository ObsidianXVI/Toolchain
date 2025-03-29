library toolchain.dart.boilerplate.http_apis.define;

import 'dart:convert';
import 'dart:io';

class API {
  final String apiName;
  final List<RouteSegment> routes;

  const API({
    required this.apiName,
    required this.routes,
  });

  Future<void> handleRequest(HttpRequest request) async {
    bool isValid = false;
    for (final route in routes) {
      if (route.routeName == request.uri.pathSegments[0]) {
        isValid = true;
        await route.handleRequestToRoute(request, 0);
        break;
      }
    }

    if (!isValid) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write({
          "msg":
              "The requested route segment '${request.uri.pathSegments[0]}' does not exist.",
        });
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
      endpoint!.handleRequestToEndpoint(request);
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
          ..write({
            "msg":
                "The requested route segment '${request.uri.pathSegments[routeSegIndex + 1]}' does not exist.",
          });
        return;
      }
    }
  }
}

enum EndpointType {
  get('GET'),
  post('POST'),
  put('PUT'),
  patch('PATCH'),
  delete('DELETE'),
  ;

  final String method;
  const EndpointType(this.method);
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

base class Endpoint {
  final List<EndpointType> endpointTypes;
  final List<Param> queryParameters;
  final List<Param>? bodyParameters;
  final bool requiresAuth;
  final Future<int> Function({
    required T? Function<T>(String paramName) getParam,
    required void Function(int statusCode, String issue) raise,
  }) handleRequest;

  const Endpoint({
    required this.endpointTypes,
    required this.queryParameters,
    required this.bodyParameters,
    required this.handleRequest,
    required this.requiresAuth,
  });

  Future<void> handleRequestToEndpoint(HttpRequest request) async {
    final Map<String, Object?> payload;
    if (requiresAuth) {
      if (request.headers.value(HellcatHeaders.authorization.header) == null) {
        print(
            "This endpoint requires an Authorization header to be passed in the 'Bearer <TOKEN>' format, but said header is missing.");
        request.response
          ..statusCode = HttpStatus.unauthorized
          ..write({
            'msg':
                "This endpoint requires an Authorization header to be passed in the 'Bearer <TOKEN>' format, but said header is missing."
          });
        return;
      } else if (!request.headers
          .value(HellcatHeaders.authorization.header)!
          .startsWith('Bearer ')) {
        print(
            "This endpoint requires an Authorization header to be passed in the 'Bearer <TOKEN>' format, but the given header is not in the required format.");
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write({
            'msg':
                "This endpoint requires an Authorization header to be passed in the 'Bearer <TOKEN>' format, but the given header is not in the required format."
          });
        return;
      }
    }
    if (endpointTypes.map((t) => t.method).contains(request.method)) {
      if (bodyParameters != null) {
        try {
          payload = jsonDecode(await utf8.decodeStream(request));
        } catch (e, __) {
          print(
              "This endpoint expects a valid request body, but an error occurred when parsing it.");
          request.response
            ..statusCode = HttpStatus.badRequest
            ..write({
              'msg':
                  "This endpoint expects a valid request body, but an error occurred when parsing it.",
              'error': e,
            });
          return;
        }
      } else {
        payload = const {};
      }
    } else {
      request.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..write({
          'msg':
              "This endpoint only supports ${endpointTypes.map((t) => t.method).join(', ')} but the request's method is ${request.method}."
        });
      return;
    }

    bool isValidReq = true;
    final List<String> issues = [];
    final Map<String, dynamic> paramStore = {
      if (requiresAuth) ...{
        HellcatHeaders.authorization.header: request.headers
            .value(HellcatHeaders.authorization.header)!
            .substring(7),
        HellcatHeaders.email.header:
            request.headers.value(HellcatHeaders.email.header),
        HellcatHeaders.uid.header:
            request.headers.value(HellcatHeaders.uid.header),
        HellcatHeaders.verified.header:
            request.headers.value(HellcatHeaders.verified.header),
        if (request.headers.value(HellcatHeaders.claims.header) != null)
          HellcatHeaders.claims.header:
              jsonDecode(request.headers.value(HellcatHeaders.claims.header)!),
      }
    };
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

    if (!isValidReq) {
      print(
          "Malformed parameters (either missing or invalid types) in query/body.");
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write({
          "msg":
              "Malformed parameters (either missing or invalid types) in query/body.",
          "issues": issues,
        });
      return;
    } else {
      T? getParam<T>(String paramName) => paramStore[paramName] as T;
      final status = await handleRequest(
        getParam: getParam,
        raise: (statusCode, issue) {
          request.response
            ..statusCode = statusCode
            ..write({'msg': issue});
        },
      );
      request.response.statusCode = status;
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

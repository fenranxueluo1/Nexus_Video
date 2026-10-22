class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final int? code;

  bool get isLoginRequired => code == -101 || statusCode == 401;
  bool get isRiskControl => code == -352 || code == -412 || statusCode == 412;
  bool get isNotFound => code == -404 || statusCode == 404;

  @override
  String toString() => message;
}

class BiliServiceException extends ApiException {
  const BiliServiceException(super.message, {super.code, super.statusCode});
}

class ApiException implements Exception {
  final int statusCode;
  final String message;

  const ApiException({required this.statusCode, required this.message});

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class TokenResponse {
  final String accessToken;
  final String tokenType;

  const TokenResponse({required this.accessToken, this.tokenType = 'bearer'});

  factory TokenResponse.fromJson(Map<String, dynamic> j) => TokenResponse(
    accessToken: j['access_token'] as String,
    tokenType: (j['token_type'] as String?) ?? 'bearer',
  );
}

class UserResponse {
  final String id;
  final String email;
  final String username;
  final DateTime createdAt;

  const UserResponse({
    required this.id,
    required this.email,
    required this.username,
    required this.createdAt,
  });

  factory UserResponse.fromJson(Map<String, dynamic> j) => UserResponse(
    id: j['id'] as String,
    email: j['email'] as String,
    username: j['username'] as String,
    createdAt: DateTime.parse(j['created_at'] as String),
  );
}

class ImageResponse {
  final String id;
  final String imagePath;
  final DateTime uploadedAt;

  const ImageResponse({
    required this.id,
    required this.imagePath,
    required this.uploadedAt,
  });

  factory ImageResponse.fromJson(Map<String, dynamic> j) => ImageResponse(
    id: j['id'] as String,
    imagePath: j['image_path'] as String,
    uploadedAt: DateTime.parse(j['uploaded_at'] as String),
  );
}

class AnnotationItem {
  final int classId;
  final double x1;
  final double y1;
  final double x2;
  final double y2;

  const AnnotationItem({
    required this.classId,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  factory AnnotationItem.fromJson(Map<String, dynamic> j) => AnnotationItem(
    classId: (j['class_id'] as num).toInt(),
    x1: (j['x1'] as num).toDouble(),
    y1: (j['y1'] as num).toDouble(),
    x2: (j['x2'] as num).toDouble(),
    y2: (j['y2'] as num).toDouble(),
  );
}

class InferenceResponse {
  final String extractedText;
  final List<AnnotationItem> annotations;

  const InferenceResponse({
    required this.extractedText,
    required this.annotations,
  });

  factory InferenceResponse.fromJson(Map<String, dynamic> j) =>
      InferenceResponse(
        extractedText: j['extracted_text'] as String,
        annotations: (j['annotations'] as List<dynamic>)
            .map((e) => AnnotationItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

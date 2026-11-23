# 사진 글자 인식(ML Kit): 플러그인이 모든 언어 모듈을 참조하지만, 앱에는 한국어 모듈만 넣는다.
# (android/app/build.gradle.kts의 text-recognition-korean) 나머지 언어 모듈이 없다고 R8이
# 릴리스 빌드를 멈추지 않게 한다. 앱은 한국어 인식기만 만들므로 실행 중에는 이 클래스들을 쓰지 않는다.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**

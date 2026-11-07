# Daily voice calls (WebRTC native code calls back into these by name)
-keep class co.daily.** { *; }
-keep class org.webrtc.** { *; }
-dontwarn co.daily.**
-dontwarn org.webrtc.**

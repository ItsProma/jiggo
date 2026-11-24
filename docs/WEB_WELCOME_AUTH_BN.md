# Website Welcome ও Google login domain

এই branch main থেকে আলাদা; live website বদলায়নি। Android-এর login layout আগেরটাই থাকবে।
নতুন WebLoginWelcome শুধু kIsWeb-এ ব্যবহার হয়। Google/Email/Guest/Privacy callback আগের AuthService-ই ব্যবহার করে।

## প্রথমে local review

PowerShell-এ:
```powershell
cd D:\jiggo
git status --short
git fetch origin
git switch codex/web-welcome-auth-domain
flutter analyze
flutter test
flutter run -d web-server --web-hostname=localhost --web-port=7357 --dart-define-from-file="D:\jiggo-web-config.json"
```

বর্তমান branch-এ uncommitted কাজ থাকলে আগে সেটি সংরক্ষণ করুন; discard/force করবেন না।
localhost:7357 খুলে logout করে নতুন প্রথম পেজ দেখুন। Google ও email login, Guest, Privacy এবং Bangla/English পরীক্ষা করুন।
320px মোবাইল, desktop এবং বড় text-এ layout পরীক্ষা করুন।
এই branch-এর automated test এখনো চালানো হয়নি: execution workspace unavailable ছিল।

## jiggo.debcreatives.net দিয়ে Google auth

শুধু UI-তে লেখা বদলালে Google account chooser-এর domain বদলাবে না।

১. Vercel-এ আগে এই branch-এর Preview deployment দিয়ে proxy যাচাই করুন।
root vercel.json-এর auth rewrites যদি আপনার deployment build/publication process-এ বাদ পড়ে যায়, সেগুলো deployment-এর root-এ রাখুন।
অন্য vercel.json/settings থাকলে rewrite মিলিয়ে যোগ করুন, build/output setting মুছবেন না।
/__/auth/:path* থেকে jiggo-bee33.firebaseapp.com-এ transparent proxy হবে; browser redirect নয়।
init.json-ও proxy করা আছে। Auth paths-এ অতিরিক্ত CDN caching যোগ করবেন না।

২. Firebase Console → Authentication → Settings → Authorized domains-এ jiggo.debcreatives.net যোগ করুন।
পুরোনো firebaseapp.com এবং localhost entry থাকলে মুছবেন না।

৩. Google Cloud Console-এ jiggo-bee33 project বেছে Google Auth Platform → Clients খুলুন।
Firebase Google provider-এর ব্যবহৃত Web OAuth client-টিই বেছে নিন।
Authorized JavaScript origins-এ https://jiggo.debcreatives.net এবং Authorized redirect URIs-এ নিচের exact URL যোগ করুন:
https://jiggo.debcreatives.net/__/auth/handler
আগের redirect URI রাখুন।
Branding-এ app name Jiggo এবং প্রকৃত homepage/privacy URL দিন। Google verification চাইলে তার প্রক্রিয়া শেষ করতে হবে।
Web client secret code-এ বা chat-এ বসাবেন না।

৪. Proxy এবং Console settings যাচাইয়ের পরে production web build-এ যুক্ত করুন:
--dart-define=FIREBASE_AUTH_DOMAIN=jiggo.debcreatives.net
অথবা ব্যবহৃত web build config JSON-এ:
"FIREBASE_AUTH_DOMAIN": "jiggo.debcreatives.net"

এটি Flutter compile-time define; শুধু Vercel environment variable যোগ করলেই build-এ ঢুকবে না।
আপনার build command/script-কে define পাঠাতে হবে।
Production domain-এ deploy হওয়ার পর Google login/logout, email verification এবং password reset পরীক্ষা করুন।
Auth helper path-এর response-এ Flutter homepage নয়, Firebase handler আসতে হবে।

Default build-এ আগের firebaseapp.com domain থাকে। এতে setup সম্পন্ন হওয়ার আগে sign-in নষ্ট হবে না।
Rollback: নতুন define বাদ দিয়ে আবার web build/deploy; proxy ও পুরোনো redirect entry রাখা যায়।

Sources:
https://firebase.google.com/docs/auth/web/google-signin#customizing-the-redirect-domain-for-google-sign-in
https://firebase.google.com/docs/auth/web/redirect-best-practices#option_3_proxy_auth_requests_to_firebaseappcom
https://vercel.com/docs/routing/rewrites

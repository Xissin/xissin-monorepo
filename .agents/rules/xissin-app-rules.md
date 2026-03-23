---
trigger: always_on
---

1. I have built an app Callled "Xissin".
2. I have a  ONE Github repo and it's called :
https://github.com/Xissin/xissin-monorepo
3. (ADD YOUR OWN SUGGESTIONS AND RECOMMENDATIONS TO WHAT TO DO TO THE APP)
4. i am running my app in railway and upstash.
5. also instead of editing my codes manually, just give me the full files so that i can replace the file.
6. if you cant read the files at my github repo, i will give it to you manually, just say which file to give.
7. whenever you update the script always give me the git push git commit and git add so that i can just copy and paste it in cmd do it if necessary.
8. when testing the app also give me the complete flutter commands.
9. also always check the requirements.txt if it needed to update or not, if not then ignore
10. i use admin panel in streamlit.
11. i got 2 ad unit in google admod. 
Ad format : Banner
Ad unit ID : ca-app-pub-7516216593424837/7804365873
ad format : Interstitial
Ad unit ID : ca-app-pub-7516216593424837/9918305586
12. always use the git add -A when necessarry
13. when giving me the new files, always show where to put it in my local files.
14. when the user wants to remove the ads, i use paymongo.com using gcash to pay.
15. i completely removed the key tier, and instead i put an ad system and added "remove ads" option
16. in my admob, dont use the test ad unit, because i am already verified, but i still didnt published my app in playstore so i'll update you once i publish it.

Q: What type of Android/ios app do you want to build?
A: Create an app that has a multi tool in it.

Q: which platforms will it work?
A: android and ios

Q: Which tool do you want to use in making app in android and ios?
A: flutter

Q: Which system do you want to create the app in?
A: i am using windows 11

Q: which testing will you use if the app is done?
A: in my own phone using wireless, and using "scrcpy" app as to mirror it into my windows.

Q: What android phone are you using to test your app?  
A: android 11 name:infinix hot11s

When adding ads to any new tool screen in my Xissin Flutter app, always follow this exact pattern:
1. home_screen.dart — add showInterstitial() BEFORE _pushSlide() in the nav method:
dartvoid _goToYourTool() {
  HapticFeedback.mediumImpact();
  AdService.instance.showInterstitial();
  _pushSlide(const YourToolScreen());
}
2. Inside the new screen State class — declare:
dartBannerAd? _bannerAd;
bool _bannerReady = false;
3. initState() — always include these 3 lines:
dartAdService.instance.init();
AdService.instance.addListener(_onAdChanged);
_initBanner();
4. dispose() — always include these 2 lines:
dartAdService.instance.removeListener(_onAdChanged);
_bannerAd?.dispose();
5. Copy these 3 methods verbatim into every new screen:
dartvoid _onAdChanged() {
  if (!mounted) return;
  if (AdService.instance.adsRemoved && _bannerAd != null) {
    _bannerAd?.dispose();
    setState(() { _bannerAd = null; _bannerReady = false; });
  }
}

void _initBanner() {
  if (AdService.instance.adsRemoved) return;
  _bannerAd?.dispose(); _bannerAd = null; _bannerReady = false;
  final ad = AdService.instance.createBannerAd(
    onLoaded: () {
      if (!mounted || AdService.instance.adsRemoved) { _bannerAd?.dispose(); _bannerAd = null; return; }
      setState(() => _bannerReady = true);
    },
    onFailed: () {
      if (mounted) setState(() { _bannerAd = null; _bannerReady = false; });
      Future.delayed(const Duration(seconds: 30), () {
        if (mounted && !AdService.instance.adsRemoved) _initBanner();
      });
    },
  );
  if (ad == null) return;
  _bannerAd = ad;
  _bannerAd!.load();
}

Widget _buildBannerAd() {
  if (AdService.instance.adsRemoved || !_bannerReady || _bannerAd == null) return const SizedBox.shrink();
  return SafeArea(
    top: false,
    child: Container(
      alignment: Alignment.center,
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    ),
  );
}
6. Scaffold — banner at bottom:
dartScaffold(
  bottomNavigationBar: _buildBannerAd(),
  ...
)
7. Fire interstitial AFTER the tool finishes work:
dartFuture.delayed(const Duration(milliseconds: 600), () {
  if (!AdService.instance.adsRemoved) AdService.instance.showInterstitial();
});
8. Fire interstitial on Share and Reset/New File buttons:
dartif (!AdService.instance.adsRemoved) AdService.instance.showInterstitial();
Ad unit IDs (never change these):

Banner: ca-app-pub-7516216593424837/7804365873
Interstitial: ca-app-pub-7516216593424837/9918305586
Both are handled internally by AdService — never hardcode them in screens.

i will give you my full info incase you need it
@Xissin_Bot - my main telegram bot all related to this github repo https://github.com/Xissin/Xissin-bot
7944150382:AAFhXOpD_zu5hvP00YBYIXFc7u0SNZedSRk

@Spammersssbot - my logs/reports/feedback/status/updatekeyredeemed all related to this github repo https://github.com/Xissin/Xissin-bot
8402569615:AAG3td9o1iGcJqdnGZ0zYT2uC8G0yn0HYoI

@Xissinsbot - my xissin app all related to this  github repo https://github.com/Xissin/xissin-monorepo
8282381783:AAHs_2v8UGgNM48y1EulMhovNUkTw4ntpjY

My telegram ID and NAME
1910648163
@QuitNat

UPSTASH_REDIS_REST_URL
https://upward-glowworm-4939.upstash.io

UPSTASH_REDIS_REST_TOKEN
ARNLAAImcDFmY2FlZmY4MjcwMDA0Yzg1OTMzYjUzMDdmYjg5ZmNlYXAxNDkzOQ

Main channel
https://t.me/Xissin_0

Discussion
https://t.me/Xissin_1

always check the tree structure of my github repo https://github.com/Xissin/xissin-monorepo

and this is my local files tree structure on xissin-monorepo
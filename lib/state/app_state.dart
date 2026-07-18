import 'package:flutter/widgets.dart';

/// Mock session state for the screens-only pass.
///
/// Sign-in swaps content in place (org cards appear, locked cards disappear) —
/// it never produces a separate "logged-in app". Real auth/API wiring lands in
/// the next pass.
class AppState extends ChangeNotifier {
  bool signedIn = false;
  bool onboarded = false;

  // Local node / server mock state.
  bool serving = true;
  bool serveOnNetwork = true;
  bool startAtLogin = true;
  bool pauseOnLowBattery = true;

  // Chat header selections.
  String selectedModel = 'Qwen 3.5 0.8B';
  String selectedModelQuant = 'Q4_K_M';
  String selectedPersona = 'Concise Analyst';

  void signIn() {
    signedIn = true;
    notifyListeners();
  }

  void signOut() {
    signedIn = false;
    notifyListeners();
  }

  void completeOnboarding() {
    onboarded = true;
    notifyListeners();
  }

  void setServing(bool v) {
    serving = v;
    notifyListeners();
  }

  void setServeOnNetwork(bool v) {
    serveOnNetwork = v;
    notifyListeners();
  }

  void setStartAtLogin(bool v) {
    startAtLogin = v;
    notifyListeners();
  }

  void setPauseOnLowBattery(bool v) {
    pauseOnLowBattery = v;
    notifyListeners();
  }

  void selectModel(String name, String quant) {
    selectedModel = name;
    selectedModelQuant = quant;
    notifyListeners();
  }

  void selectPersona(String name) {
    selectedPersona = name;
    notifyListeners();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

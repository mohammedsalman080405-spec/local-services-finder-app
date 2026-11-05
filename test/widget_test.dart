import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:local_services_finder/auth_service.dart';
import 'package:local_services_finder/main.dart';

const testSession = AuthSession(
  user: AuthUser(id: 42, fullName: 'Test User', email: 'test@example.com'),
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
);

void configurePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('login submits email and password and accepts the returned session', (
    tester,
  ) async {
    configurePhoneViewport(tester);
    String? submittedEmail;
    String? submittedPassword;
    AuthSession? acceptedSession;

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          onLogin: ({required email, required password}) async {
            submittedEmail = email;
            submittedPassword = password;
            return testSession;
          },
          onRegister: ({required fullName, required email, required password}) async => testSession,
          onAuthenticated: (session) => acceptedSession = session,
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField).at(0), 'test@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'correct horse battery');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Login'));
    await tester.tap(find.widgetWithText(FilledButton, 'Login'));
    await tester.pumpAndSettle();

    expect(submittedEmail, 'test@example.com');
    expect(submittedPassword, 'correct horse battery');
    expect(acceptedSession, testSession);
  });

  testWidgets('registration collects name, email, password and confirmation', (
    tester,
  ) async {
    configurePhoneViewport(tester);
    String? registeredName;
    String? registeredEmail;
    String? registeredPassword;

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          onLogin: ({required email, required password}) async => testSession,
          onRegister: ({required fullName, required email, required password}) async {
            registeredName = fullName;
            registeredEmail = email;
            registeredPassword = password;
            return testSession;
          },
          onAuthenticated: (_) {},
        ),
      ),
    );
    await tester.ensureVisible(find.text('Sign Up'));
    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Test User');
    await tester.enterText(fields.at(1), 'test@example.com');
    await tester.enterText(fields.at(2), 'correct horse battery');
    await tester.enterText(fields.at(3), 'correct horse battery');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Create Account').last);
    await tester.tap(find.widgetWithText(FilledButton, 'Create Account').last);
    await tester.pumpAndSettle();

    expect(registeredName, 'Test User');
    expect(registeredEmail, 'test@example.com');
    expect(registeredPassword, 'correct horse battery');
  });
}

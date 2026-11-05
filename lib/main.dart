import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'auth_service.dart';
import 'location_service.dart';
import 'location_widgets.dart';

void main() => runApp(const LocalServicesApp());

const navy = Color(0xFF142B4B);
const blue = Color(0xFF1677F2);
const ink = Color(0xFF142B4B);
const muted = Color(0xFF75849A);
const canvas = Color(0xFFF5F8FC);
const lightBlue = Color(0xFFE8F2FF);
const borderColor = Color(0xFFE5ECF5);

class LocalServicesApp extends StatelessWidget {
  const LocalServicesApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Nearby',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: canvas,
      colorScheme: ColorScheme.fromSeed(seedColor: blue),
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: ink,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 70,
        backgroundColor: Colors.white,
        indicatorColor: lightBlue,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected) ? blue : muted,
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
    ),
    home: const AuthGate(),
  );
}

final authService = AuthService();

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  AuthUser? user;
  LocationService? locations;
  String? restoreError;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      user = await authService.restoreSession();
      if (user != null) locations = LocationService(authService);
    } on AuthApiException catch (error) {
      restoreError = error.message;
    } catch (_) {
      restoreError =
          'Unable to restore your session. Please try signing in again.';
    }
    if (mounted) setState(() => loading = false);
  }

  void _authenticated(AuthSession session) {
    if (!mounted) return;
    setState(() {
      user = session.user;
      locations = LocationService(authService);
      restoreError = null;
    });
  }

  Future<void> _logout() async {
    try {
      await authService.logout();
    } catch (_) {
      await authService.clearSession();
    }
    if (mounted) {
      setState(() {
        user = null;
        locations = null;
        restoreError = null;
      });
    }
  }

  Future<void> _saveProfile(String n, String e) async {
    if (mounted && user != null) {
      setState(() => user = AuthUser(id: user!.id, fullName: n, email: e));
    }
  }

  @override
  Widget build(BuildContext context) => loading
      ? const Scaffold(body: Center(child: CircularProgressIndicator()))
      : user == null
      ? LoginScreen(
          initialError: restoreError,
          onLogin: authService.login,
          onRegister: authService.register,
          onAuthenticated: _authenticated,
        )
      : FinderShell(
          userName: user!.fullName,
          email: user!.email,
          onLogout: _logout,
          onSaveProfile: _saveProfile,
          locations: locations!,
        );
}

class LoginScreen extends StatefulWidget {
  final String? initialError;
  final Future<AuthSession> Function({
    required String email,
    required String password,
  })
  onLogin;
  final Future<AuthSession> Function({
    required String fullName,
    required String email,
    required String password,
  })
  onRegister;
  final ValueChanged<AuthSession> onAuthenticated;

  const LoginScreen({
    super.key,
    required this.onLogin,
    required this.onRegister,
    required this.onAuthenticated,
    this.initialError,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  final confirmPassword = TextEditingController();
  bool obscure = true, registering = false, busy = false;

  @override
  void initState() {
    super.initState();
    final message = widget.initialError;
    if (message != null && message.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showMessage(message);
      });
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  void _showMessage(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => Scaffold(
    body: LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                height: 365,
                padding: const EdgeInsets.fromLTRB(25, 55, 25, 35),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF0C2B4B),
                      Color(0xFF1265A5),
                      Color(0xFF071B34),
                    ],
                  ),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(34),
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -18,
                      top: 15,
                      bottom: 0,
                      child: Opacity(
                        opacity: .84,
                        child: Image.network(
                          'https://images.unsplash.com/photo-1621905251189-08b45d6a269e?auto=format&fit=crop&w=500&q=85',
                          width: box.maxWidth < 430 ? 118 : 190,
                          height: 280,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.engineering_rounded,
                            size: 180,
                            color: Color(0x5565D9FF),
                          ),
                        ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Spacer(),
                        const Icon(
                          Icons.location_on,
                          color: Color(0xFF5ED8FF),
                          size: 58,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Local Services\nFinder',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 36,
                            height: 1.02,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Find trusted service providers\nnear you',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            height: 1.4,
                          ),
                        ),
                        const Spacer(),
                      ],
                    ),
                  ],
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -25),
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 18),
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAFBFF),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: navy.withValues(alpha: .12),
                        blurRadius: 28,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Form(
                    key: form,
                    child: Column(
                      children: [
                        Text(
                          registering ? 'Create Account' : 'Welcome Back',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF101A30),
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          registering
                              ? 'Sign up for your Local Services Finder account'
                              : 'Login to your Local Services Finder account',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF52617D),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (registering) ...[
                          TextFormField(
                            controller: name,
                            decoration: authDecoration(
                              'Full Name',
                              Icons.person_outline,
                            ),
                            validator: (s) => (s == null || s.trim().length < 2)
                                ? 'Enter your full name'
                                : null,
                          ),
                          const SizedBox(height: 12),
                        ],
                        TextFormField(
                          controller: email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: authDecoration(
                            'Email Address',
                            Icons.mail_outline,
                          ),
                          validator: (s) {
                            final v = s?.trim() ?? '';
                            if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                .hasMatch(v)) {
                              return 'Enter a valid email address';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: password,
                          obscureText: obscure,
                          decoration:
                              authDecoration(
                                'Password',
                                Icons.lock_outline,
                              ).copyWith(
                                suffixIcon: IconButton(
                                  onPressed: () =>
                                      setState(() => obscure = !obscure),
                                  icon: Icon(
                                    obscure
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                ),
                              ),
                          validator: (s) => (s == null || s.length < 8)
                              ? 'Password must be at least 8 characters'
                              : null,
                        ),
                        if (registering) ...[
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: confirmPassword,
                            obscureText: obscure,
                            decoration: authDecoration(
                              'Confirm Password',
                              Icons.lock_outline,
                            ),
                            validator: (value) => value != password.text
                                ? 'Passwords do not match'
                                : null,
                          ),
                        ],
                        if (!registering)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _forgot,
                              child: const Text(
                                'Forgot Password?',
                                style: TextStyle(
                                  color: Color(0xFF0754C7),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 7),
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: FilledButton(
                            onPressed: busy ? null : _submit,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF0E4677),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                            child: busy
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    registering ? 'Create Account' : 'Login',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: const [
                            Expanded(child: Divider()),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'Or continue with',
                                style: TextStyle(color: Color(0xFF52617D)),
                              ),
                            ),
                            Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _socialUnavailable('Google'),
                                icon: const Icon(
                                  Icons.g_mobiledata,
                                  size: 25,
                                  color: Colors.red,
                                ),
                                label: const Text('Google'),
                                style: authSocialStyle(),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _socialUnavailable('Apple'),
                                icon: const Icon(Icons.apple, size: 23),
                                label: const Text('Apple'),
                                style: authSocialStyle(),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          alignment: WrapAlignment.center,
                          children: [
                            Text(
                              registering
                                  ? 'Already have an account? '
                                  : 'Don’t have an account? ',
                              style: const TextStyle(color: Color(0xFF52617D)),
                            ),
                            GestureDetector(
                              onTap: () => setState(() {
                                registering = !registering;
                                form.currentState?.reset();
                              }),
                              child: Text(
                                registering ? 'Login' : 'Sign Up',
                                style: const TextStyle(
                                  color: Color(0xFF0754C7),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Connected to $authApiBaseUrl',
                          style: TextStyle(fontSize: 10, color: muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  InputDecoration authDecoration(String label, IconData icon) =>
      InputDecoration(
        hintText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF52617D)),
        filled: true,
        fillColor: const Color(0xFFF8FAFE),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 17,
          horizontal: 16,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFBCC9DB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: blue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
      );
  ButtonStyle authSocialStyle() => OutlinedButton.styleFrom(
    foregroundColor: ink,
    minimumSize: const Size(0, 48),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    side: const BorderSide(color: Color(0xFFBCC9DB)),
  );
  Future<void> _submit() async {
    if (busy || !(form.currentState?.validate() ?? false)) return;
    setState(() => busy = true);
    try {
      final session = registering
          ? await widget.onRegister(
              fullName: name.text.trim(),
              email: email.text.trim(),
              password: password.text,
            )
          : await widget.onLogin(
              email: email.text.trim(),
              password: password.text,
            );
      if (!mounted) return;
      _showMessage(
        registering
            ? 'Account created successfully.'
            : 'Signed in successfully.',
      );
      widget.onAuthenticated(session);
    } on AuthApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Authentication failed. Please try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _forgot() {
    if (email.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email address first.')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Password reset requires a configured backend.'),
      ),
    );
  }

  void _socialUnavailable(String provider) => ScaffoldMessenger.of(context)
      .showSnackBar(
        SnackBar(
          content: Text('$provider sign-in requires OAuth configuration.'),
        ),
      );
}

InputDecoration authDecoration(String hint, IconData icon) => InputDecoration(
  hintText: hint,
  prefixIcon: Icon(icon),
  filled: true,
  fillColor: Colors.white,
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)),
);

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notifications')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.notifications_none_rounded, size: 58, color: blue),
            const SizedBox(height: 14),
            const Text(
              "You're all caught up!",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Notifications will appear here when the authenticated notifications API is connected.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, height: 1.45),
            ),
          ],
        ),
      ),
    ),
  );
}

const categories = [
  ('Electrician', Icons.electrical_services),
  ('Plumber', Icons.plumbing),
  ('Carpenter', Icons.handyman),
  ('AC Repair', Icons.ac_unit),
  ('Home Cleaning', Icons.cleaning_services),
  ('Painting', Icons.format_paint),
  ('Appliance Repair', Icons.kitchen),
  ('More', Icons.grid_view),
];

IconData serviceIcon(String category) =>
    categories
        .where((entry) => entry.$1 == category)
        .map((entry) => entry.$2)
        .firstOrNull ??
    Icons.home_repair_service;

const categoryServices = <String, List<String>>{
  'Electrician': [
    'Electrical Repair',
    'Wiring Installation',
    'Switchboard Repair',
    'Fan Installation',
    'Lighting Installation',
  ],
  'Plumber': [
    'Pipe Repair',
    'Tap Installation',
    'Drain Cleaning',
    'Leak Repair',
  ],
  'Carpenter': [
    'Furniture Repair',
    'Door Repair',
    'Shelf Installation',
    'Custom Carpentry',
  ],
  'AC Repair': ['AC Service', 'AC Repair', 'Gas Refill', 'Installation'],
  'Home Cleaning': [
    'Full Home Cleaning',
    'Kitchen Cleaning',
    'Bathroom Cleaning',
    'Deep Cleaning',
  ],
  'Painting': ['Interior Painting', 'Exterior Painting', 'Wall Touch-up'],
  'Appliance Repair': [
    'Refrigerator Repair',
    'Washing Machine Repair',
    'Microwave Repair',
  ],
};

class ServiceRequest {
  final int? id, providerId;
  final String service, issue, date, time, location;
  final String status;
  final String providerName, category;
  ServiceRequest(
    this.service,
    this.issue,
    this.date,
    this.time,
    this.location, {
    this.id,
    this.providerId,
    this.status = 'Pending',
    this.providerName = 'Provider',
    this.category = 'Electrician',
  });

  factory ServiceRequest.fromJson(Map<String, dynamic> json) => ServiceRequest(
    json['service'] as String,
    json['issue'] as String,
    json['date'] as String,
    json['time'] as String,
    json['location'] as String,
    id: json['id'] as int?,
    providerId: json['provider_id'] as int?,
    status: json['status'] as String? ?? 'Pending',
    providerName: json['provider_name'] as String? ?? 'Provider',
    category: json['category'] as String? ?? '',
  );

  Map<String, dynamic> toPayload(int selectedProviderId) => {
    'provider_id': selectedProviderId,
    'service': service,
    'issue': issue,
    'date': date,
    'time': time,
    'location': location,
  };
}

class FinderShell extends StatefulWidget {
  final String userName, email;
  final Future<void> Function() onLogout;
  final Future<void> Function(String, String) onSaveProfile;
  final LocationService locations;
  const FinderShell({
    super.key,
    required this.userName,
    required this.email,
    required this.onLogout,
    required this.onSaveProfile,
    required this.locations,
  });
  @override
  State<FinderShell> createState() => _FinderShellState();
}

class _FinderShellState extends State<FinderShell> {
  int tab = 0;
  String category = 'Electrician';
  String searchQuery = '';
  final List<ServiceRequest> requests = [];

  @override
  void initState() {
    super.initState();
    widget.locations.load();
    _loadRequests();
  }

  void openSearch(String service) {
    setState(() {
      category = service == 'More' ? '' : service;
      tab = 1;
    });
  }

  Future<void> _loadRequests() async {
    try {
      final result = await authService.getAuthenticated('/api/requests');
      final rows = (result['requests'] as List)
          .map(
            (value) => ServiceRequest.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList();
      if (mounted) {
        setState(() {
          requests
            ..clear()
            ..addAll(rows);
        });
      }
    } catch (_) {
      // Preserve the last loaded requests if the API is temporarily unavailable.
    }
  }

  Future<void> _cancelRequest(ServiceRequest request) async {
    if (request.id == null) return;
    final result = await authService.postAuthenticated(
      '/api/requests/${request.id}/cancel',
      {},
    );
    final updated = ServiceRequest.fromJson(
      Map<String, dynamic>.from(result['request'] as Map),
    );
    if (!mounted) return;
    setState(() {
      final index = requests.indexWhere((item) => item.id == updated.id);
      if (index >= 0) requests[index] = updated;
    });
  }

  void openRequest(NearbyProvider provider) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => RequestServiceScreen(
        provider: provider,
        locations: widget.locations,
        onSubmit: (r) async {
          final response = await authService.postAuthenticated(
            '/api/requests',
            r.toPayload(provider.id),
          );
          final saved = ServiceRequest.fromJson(
            Map<String, dynamic>.from(response['request'] as Map),
          );
          if (mounted) setState(() => requests.insert(0, saved));
          return saved;
        },
      ),
    ),
  );
  void openProvider(NearbyProvider provider) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ProviderDetailsScreen(
        provider: provider,
        onRequest: () => openRequest(provider),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        onCategory: openSearch,
        onSearch: () => openSearch(searchQuery.trim().isEmpty ? category : ''),
        onSearchText: (value) => searchQuery = value,
        onProvider: openProvider,
        userName: widget.userName,
        locations: widget.locations,
      ),
      SearchScreen(
        category: category,
        initialQuery: searchQuery,
        onMap: () => setState(() => tab = 2),
        onCategory: (s) => setState(() => category = s),
        onProvider: openProvider,
        locations: widget.locations,
      ),
      MapScreen(
        category: category,
        onCategory: (s) => setState(() => category = s),
        onProvider: openProvider,
        locations: widget.locations,
      ),
      RequestsScreen(requests: requests, onCancel: _cancelRequest),
      ProfileScreen(
        userName: widget.userName,
        email: widget.email,
        onLogout: widget.onLogout,
        onSaveProfile: widget.onSaveProfile,
        locations: widget.locations,
      ),
    ];
    return Scaffold(
      body: IndexedStack(index: tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFE4F0FF),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map_rounded),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment_rounded),
            label: 'Requests',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final ValueChanged<String> onCategory;
  final VoidCallback onSearch;
  final ValueChanged<String> onSearchText;
  final ValueChanged<NearbyProvider> onProvider;
  final String userName;
  final LocationService locations;
  const HomeScreen({
    super.key,
    required this.onCategory,
    required this.onSearch,
    required this.onSearchText,
    required this.onProvider,
    required this.userName,
    required this.locations,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<List<NearbyProvider>>? providers;
  final searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.locations.addListener(_locationChanged);
    _loadProviders();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.locations != widget.locations) {
      oldWidget.locations.removeListener(_locationChanged);
      widget.locations.addListener(_locationChanged);
      _loadProviders();
    }
  }

  @override
  void dispose() {
    widget.locations.removeListener(_locationChanged);
    searchController.dispose();
    super.dispose();
  }

  void _locationChanged() {
    if (mounted) setState(_loadProviders);
  }

  void _loadProviders() {
    providers = widget.locations.selected == null
        ? null
        : widget.locations.nearbyProviders(
            category: 'Electrician',
            radiusKm: 5,
          );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final contentWidth = constraints.maxWidth > 960
          ? 960.0
          : constraints.maxWidth;
      return Center(
        child: SizedBox(
          width: contentWidth,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 14),
                decoration: const BoxDecoration(
                  color: lightBlue,
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(28),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hello, ${widget.userName} 👋',
                                style: TextStyle(
                                  color: ink,
                                  fontSize: 25,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Find trusted local services near you',
                                style: TextStyle(color: muted, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F9FF),
                            borderRadius: BorderRadius.circular(17),
                            border: Border.all(color: const Color(0xFFD7E6F7)),
                          ),
                          child: IconButton(
                            tooltip: 'Notifications',
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const NotificationsScreen(),
                              ),
                            ),
                            icon: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                const Icon(
                                  Icons.notifications_none_rounded,
                                  color: ink,
                                  size: 24,
                                ),
                                Positioned(
                                  right: -2,
                                  top: -2,
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: blue,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE3F0FF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: borderColor),
                      ),
                      child: LocationSelector(
                        locations: widget.locations,
                        compact: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 15),
                          const Icon(
                            Icons.search_rounded,
                            color: ink,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: searchController,
                              onChanged: widget.onSearchText,
                              onSubmitted: (_) => widget.onSearch(),
                              textInputAction: TextInputAction.search,
                              decoration: const InputDecoration(
                                hintText: 'What service do you need?',
                                border: InputBorder.none,
                                isDense: true,
                                hintStyle: TextStyle(
                                  color: muted,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          Container(width: 1, height: 27, color: borderColor),
                          IconButton(
                            tooltip: 'Search and filters',
                            onPressed: widget.onSearch,
                            icon: const Icon(Icons.tune_rounded, color: blue),
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                height: 132,
                padding: const EdgeInsets.fromLTRB(14, 12, 0, 12),
                decoration: BoxDecoration(
                  color: lightBlue,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'BOOK WITH CONFIDENCE',
                              style: TextStyle(
                                color: blue,
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Home Services at Your Doorstep',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: navy,
                            ),
                          ),
                          const SizedBox(height: 3),
                          const Text(
                            'Trusted experts, right around the corner',
                            maxLines: 2,
                            style: TextStyle(fontSize: 9, color: muted),
                          ),
                        ],
                      ),
                    ),
                    ClipRRect(
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(20),
                      ),
                      child: Image.asset(
                        'assets/images/home_services_reference_art.png',
                        width: 130,
                        height: 132,
                        fit: BoxFit.cover,
                        alignment: Alignment.centerRight,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: sectionTitle(
                  'Explore Services',
                  'View all',
                  () => widget.onCategory('More'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: LayoutBuilder(
                  builder: (context, gridConstraints) => GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: categories.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: gridConstraints.maxWidth >= 960
                          ? 6
                          : gridConstraints.maxWidth >= 760
                          ? 5
                          : 4,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: .96,
                    ),
                    itemBuilder: (context, i) {
                      final item = categories[i];
                      return InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => widget.onCategory(item.$1),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFECF0F5)),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x080F2B4B),
                                blurRadius: 10,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEDF5FF),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                child: Icon(item.$2, color: blue, size: 23),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                item.$1,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: sectionTitle(
                  'Nearby Providers',
                  'See all',
                  widget.onSearch,
                ),
              ),
              FutureBuilder<List<NearbyProvider>>(
                future: providers,
                builder: (context, snapshot) {
                  if (widget.locations.selected == null) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Select a location to find nearby providers.',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    );
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Could not load nearby services: ${snapshot.error}',
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    );
                  }
                  final items = snapshot.data ?? const <NearbyProvider>[];
                  if (items.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'No electricians are registered near this location yet.',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    );
                  }
                  return Column(
                    children: items
                        .take(2)
                        .map(
                          (provider) => ProviderTile(
                            provider: provider,
                            onTap: () => widget.onProvider(provider),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      );
    },
  );
}

Widget sectionTitle(String title, String action, VoidCallback tap) => Row(
  children: [
    Expanded(
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: ink,
        ),
      ),
    ),
    TextButton(
      onPressed: tap,
      child: Text(
        action,
        style: const TextStyle(
          color: blue,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    ),
  ],
);

class CenteredMaxWidth extends StatelessWidget {
  final double maxWidth;
  final Widget child;

  const CenteredMaxWidth({
    super.key,
    required this.maxWidth,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: constraints.maxWidth < maxWidth
            ? constraints.maxWidth
            : maxWidth,
        height: constraints.maxHeight,
        child: child,
      ),
    ),
  );
}

class SearchScreen extends StatefulWidget {
  final String category;
  final String initialQuery;
  final VoidCallback onMap;
  final ValueChanged<String> onCategory;
  final ValueChanged<NearbyProvider> onProvider;
  final LocationService locations;
  const SearchScreen({
    super.key,
    required this.category,
    required this.initialQuery,
    required this.onMap,
    required this.onCategory,
    required this.onProvider,
    required this.locations,
  });
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String filter = 'Nearest';
  bool availableOnly = false;
  late String query = widget.initialQuery;
  late final queryController = TextEditingController(text: widget.initialQuery);
  double radius = 5;
  bool loading = false;
  String? error;
  List<NearbyProvider> providers = const [];

  @override
  void initState() {
    super.initState();
    widget.locations.addListener(_locationChanged);
    _fetchProviders();
  }

  @override
  void didUpdateWidget(covariant SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialQuery != widget.initialQuery &&
        queryController.text != widget.initialQuery) {
      queryController.text = widget.initialQuery;
      query = widget.initialQuery;
    }
    if (oldWidget.category != widget.category ||
        oldWidget.locations != widget.locations) {
      if (oldWidget.locations != widget.locations) {
        oldWidget.locations.removeListener(_locationChanged);
        widget.locations.addListener(_locationChanged);
      }
      _fetchProviders();
    }
  }

  @override
  void dispose() {
    widget.locations.removeListener(_locationChanged);
    queryController.dispose();
    super.dispose();
  }

  void _locationChanged() => _fetchProviders();

  Future<void> _fetchProviders() async {
    if (widget.locations.selected == null) {
      if (mounted) {
        setState(() {
          providers = const [];
          error = null;
          loading = false;
        });
      }
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.locations.nearbyProviders(
        category: widget.category,
        radiusKm: radius,
        availableOnly: availableOnly,
      );
      if (mounted) setState(() => providers = result);
    } catch (e) {
      if (mounted) {
        setState(() {
          providers = const [];
          error = e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = query.trim().toLowerCase();
    final serviceCategory = _categoryForServiceQuery(normalizedQuery);
    var list = providers
        .where(
          (p) =>
              normalizedQuery.isEmpty ||
              (serviceCategory != null
                  ? p.category == serviceCategory
                  : '${p.name} ${p.category} ${p.description} ${p.address}'
                        .toLowerCase()
                        .contains(normalizedQuery)),
        )
        .toList();
    if (availableOnly) list = list.where((p) => p.isAvailable).toList();
    if (filter == 'Rating 4.0+') {
      list = list.where((p) => (p.rating ?? 0) >= 4).toList();
    }
    if (filter == 'Price') {
      list.sort(
        (a, b) =>
            (int.tryParse((a.price ?? '').replaceAll(RegExp(r'[^0-9]'), '')) ??
                    1 << 30)
                .compareTo(
                  int.tryParse(
                        (b.price ?? '').replaceAll(RegExp(r'[^0-9]'), ''),
                      ) ??
                      1 << 30,
                ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = constraints.maxWidth > 900
            ? 900.0
            : constraints.maxWidth;
        return SafeArea(
          child: Center(
            child: SizedBox(
              width: contentWidth,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.category.isEmpty
                                ? 'All services'
                                : widget.category,
                            style: const TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w800,
                              color: ink,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'View on map',
                          onPressed: widget.onMap,
                          icon: const Icon(Icons.map_outlined, color: blue),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: LocationSelector(
                      locations: widget.locations,
                      compact: true,
                    ),
                  ),
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: ChoiceChip(
                            label: const Text('All'),
                            selected: widget.category.isEmpty,
                            onSelected: (_) => widget.onCategory(''),
                          ),
                        ),
                        ...categories
                            .where((item) => item.$1 != 'More')
                            .map(
                              (item) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                child: ChoiceChip(
                                  avatar: Icon(item.$2, color: blue, size: 16),
                                  label: Text(item.$1),
                                  selected: widget.category == item.$1,
                                  onSelected: (_) => widget.onCategory(item.$1),
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: TextField(
                      controller: queryController,
                      onChanged: (value) => setState(() => query = value),
                      decoration: InputDecoration(
                        hintText: 'What service do you need?',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  queryController.clear();
                                  setState(() => query = '');
                                },
                              ),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: borderColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: borderColor),
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        ...[1, 3, 5, 10, 20].map(
                          (km) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: ChoiceChip(
                              label: Text('$km km'),
                              selected: radius == km,
                              onSelected: (_) {
                                setState(() => radius = km.toDouble());
                                _fetchProviders();
                              },
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: FilterChip(
                            label: const Text('Available'),
                            selected: availableOnly,
                            onSelected: (value) {
                              setState(() => availableOnly = value);
                              _fetchProviders();
                            },
                          ),
                        ),
                        ...['Nearest', 'Rating 4.0+', 'Price'].map(
                          (value) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: ChoiceChip(
                              label: Text(value),
                              selected: filter == value,
                              onSelected: (_) => setState(() => filter = value),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : error != null
                        ? _ProviderErrorState(
                            message: error!,
                            onRetry: _fetchProviders,
                          )
                        : widget.locations.selected == null
                        ? const _NoProvidersState(
                            message: 'Select a location with coordinates to find nearby providers.',
                          )
                        : list.isEmpty
                        ? _NoProvidersState(
                            message:
                                'No ${widget.category.toLowerCase()} providers were found within ${radius.toInt()} km. Try a wider radius or another location.',
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(top: 8, bottom: 16),
                            itemCount: list.length,
                            itemBuilder: (context, i) => ProviderTile(
                              provider: list[i],
                              onTap: () => widget.onProvider(list[i]),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

String? _categoryForServiceQuery(String query) {
  if (query.isEmpty) return null;
  for (final (category, _) in categories) {
    if (category.toLowerCase().contains(query) &&
        category.toLowerCase() != 'more') {
      return category;
    }
  }
  for (final entry in categoryServices.entries) {
    if (entry.value.any(
      (service) =>
          service.toLowerCase() == query ||
          service.toLowerCase().contains(query),
    )) {
      return entry.key;
    }
  }
  return null;
}

class MapScreen extends StatefulWidget {
  final String category;
  final ValueChanged<String> onCategory;
  final ValueChanged<NearbyProvider> onProvider;
  final LocationService locations;
  const MapScreen({
    super.key,
    required this.category,
    required this.onCategory,
    required this.onProvider,
    required this.locations,
  });
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  bool mapView = true, loading = false;
  double radiusKm = 5;
  String? error;
  List<NearbyProvider> providers = const [];
  GoogleMapController? controller;

  bool get mapConfigured =>
      Uri.base.queryParameters['maps_key']?.isNotEmpty ?? false;

  @override
  void initState() {
    super.initState();
    widget.locations.addListener(_locationChanged);
    _fetchProviders();
  }

  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.category != widget.category ||
        oldWidget.locations != widget.locations) {
      if (oldWidget.locations != widget.locations) {
        oldWidget.locations.removeListener(_locationChanged);
        widget.locations.addListener(_locationChanged);
      }
      _fetchProviders();
    }
  }

  @override
  void dispose() {
    widget.locations.removeListener(_locationChanged);
    controller?.dispose();
    super.dispose();
  }

  void _locationChanged() {
    _fetchProviders();
    final selected = widget.locations.selected;
    if (selected != null) {
      controller?.animateCamera(
        CameraUpdate.newLatLng(LatLng(selected.latitude, selected.longitude)),
      );
    }
  }

  Future<void> _fetchProviders() async {
    if (widget.locations.selected == null) {
      if (mounted) {
        setState(() {
          providers = const [];
          loading = false;
          error = null;
        });
      }
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.locations.nearbyProviders(
        category: widget.category,
        radiusKm: radiusKm,
      );
      if (mounted) setState(() => providers = result);
    } catch (e) {
      if (mounted) {
        setState(() {
          providers = const [];
          error = e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.locations.selected;
    final markers = <Marker>{
      if (selected != null)
        Marker(
          markerId: const MarkerId('selected-location'),
          position: LatLng(selected.latitude, selected.longitude),
          infoWindow: InfoWindow(title: selected.formattedAddress),
        ),
      ...providers.map(
        (provider) => Marker(
          markerId: MarkerId('provider-${provider.id}'),
          position: LatLng(provider.latitude, provider.longitude),
          infoWindow: InfoWindow(
            title: provider.name,
            snippet:
                '${provider.category} · ${provider.distanceKm.toStringAsFixed(1)} km',
          ),
          onTap: () => _showProvider(context, provider),
        ),
      ),
    };
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Nearby ${widget.category}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.map_outlined),
                      label: Text('Map'),
                    ),
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.list),
                      label: Text('List'),
                    ),
                  ],
                  selected: {mapView},
                  onSelectionChanged: (selection) =>
                      setState(() => mapView = selection.first),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: LocationSelector(locations: widget.locations, compact: true),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: categories
                  .where((item) => item.$1 != 'More')
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: ChoiceChip(
                        avatar: Icon(item.$2, color: blue, size: 16),
                        label: Text(item.$1),
                        selected: widget.category == item.$1,
                        onSelected: (_) => widget.onCategory(item.$1),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              children: [1, 3, 5, 10, 20]
                  .map(
                    (km) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text('$km km'),
                        selected: radiusKm == km,
                        onSelected: (_) {
                          setState(() => radiusKm = km.toDouble());
                          _fetchProviders();
                        },
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                ? _ProviderErrorState(message: error!, onRetry: _fetchProviders)
                : selected == null
                ? const _NoProvidersState(
                    message: 'Choose a saved or current location to search this category.',
                  )
                : mapView && mapConfigured
                ? Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: LatLng(selected.latitude, selected.longitude),
                          zoom: 13,
                        ),
                        markers: markers,
                        circles: {
                          Circle(
                            circleId: const CircleId('search-radius'),
                            center: LatLng(
                              selected.latitude,
                              selected.longitude,
                            ),
                            radius: radiusKm * 1000,
                            fillColor: blue.withValues(alpha: .08),
                            strokeColor: blue.withValues(alpha: .6),
                            strokeWidth: 1,
                          ),
                        },
                        onMapCreated: (value) => controller = value,
                        myLocationEnabled: false,
                        zoomControlsEnabled: true,
                      ),
                      if (providers.any((item) => item.source == 'osm'))
                        const Positioned(
                          left: 8,
                          bottom: 8,
                          child: Material(
                            color: Colors.white,
                            child: Padding(
                              padding: EdgeInsets.all(5),
                              child: Text(
                                '© OpenStreetMap contributors',
                                style: TextStyle(fontSize: 10, color: muted),
                              ),
                            ),
                          ),
                        ),
                    ],
                  )
                : mapView
                ? _MapConfigState(
                    onShowList: () => setState(() => mapView = false),
                  )
                : providers.isEmpty
                ? _NoProvidersState(
                    message:
                        'No ${widget.category.toLowerCase()} providers were found within ${radiusKm.toInt()} km. Try another radius or location.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 6, bottom: 12),
                    itemCount: providers.length,
                    itemBuilder: (context, i) => ProviderTile(
                      provider: providers[i],
                      onTap: () => widget.onProvider(providers[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _showProvider(BuildContext context, NearbyProvider provider) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                provider.name,
                style: const TextStyle(
                  color: ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${provider.category} · ${provider.distanceKm.toStringAsFixed(1)} km',
                style: const TextStyle(color: muted),
              ),
              const SizedBox(height: 5),
              Text(provider.address, style: const TextStyle(color: muted)),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onProvider(provider);
                },
                child: const Text('View Details'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapConfigState extends StatelessWidget {
  final VoidCallback onShowList;
  const _MapConfigState({required this.onShowList});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.map_outlined, size: 46, color: blue),
          const SizedBox(height: 12),
          const Text(
            'Google Maps key required',
            style: TextStyle(
              color: ink,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Set a referrer-restricted Maps JavaScript API key with the Maps JavaScript API enabled, then open this app with ?maps_key=YOUR_KEY.',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, height: 1.4, fontSize: 12),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onShowList,
            icon: const Icon(Icons.list),
            label: const Text('View provider list'),
          ),
        ],
      ),
    ),
  );
}

class _NoProvidersState extends StatelessWidget {
  final String message;
  const _NoProvidersState({
    this.message =
        'No provider records are available for this category and location.',
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.home_repair_service_outlined, size: 48, color: blue),
          const SizedBox(height: 12),
          const Text(
            'No nearby providers found',
            style: TextStyle(
              color: ink,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted, height: 1.4, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class _ProviderErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ProviderErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 44, color: blue),
          const SizedBox(height: 10),
          const Text(
            'Could not load nearby providers',
            style: TextStyle(color: ink, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 7),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

class ProviderTile extends StatelessWidget {
  final NearbyProvider provider;
  final VoidCallback onTap;
  const ProviderTile({super.key, required this.provider, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.fromLTRB(14, 5, 14, 7),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFEBEFF4)),
      ),
      child: Row(
        children: [
          Photo(
            url: provider.imageUrl,
            width: 64,
            height: 64,
            radius: 12,
            placeholderIcon: serviceIcon(provider.category),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        provider.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: ink,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (provider.isVerified)
                      const Icon(Icons.verified, size: 17, color: blue),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: lightBlue,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.location_on_rounded,
                            size: 12,
                            color: blue,
                          ),
                          Text(
                            ' ${provider.distanceKm.toStringAsFixed(1)} km',
                            style: const TextStyle(color: muted, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(serviceIcon(provider.category), color: blue, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      provider.category,
                      style: const TextStyle(
                        color: muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (provider.rating != null)
                  Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        size: 16,
                        color: Color(0xFFFFB547),
                      ),
                      Text(
                        ' ${provider.rating}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      if (provider.reviewCount != null)
                        Text(
                          ' (${provider.reviewCount})',
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                    ],
                  ),
                const SizedBox(height: 3),
                if (provider.openNow == true ||
                    (provider.openNow == null && provider.isAvailable))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      provider.openNow == true ? 'Open now' : 'Available today',
                      style: const TextStyle(
                        color: Color(0xFF23845B),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (provider.address.isNotEmpty)
                  Text(
                    provider.address,
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                if (provider.phone != null)
                  Text(
                    provider.phone!,
                    style: const TextStyle(color: muted, fontSize: 10),
                  ),
                if (provider.source == 'osm')
                  const Text(
                    '© OpenStreetMap contributors',
                    style: TextStyle(color: muted, fontSize: 9),
                  ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    if (provider.price != null)
                      Text(
                        provider.price!,
                        style: const TextStyle(
                          color: blue,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    const Spacer(),
                    const Text(
                      'View',
                      style: TextStyle(
                        color: blue,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: blue, size: 17),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class Photo extends StatelessWidget {
  final String? id;
  final String? url;
  final double width, height, radius;
  final IconData placeholderIcon;
  const Photo({
    super.key,
    this.id,
    this.url,
    required this.width,
    required this.height,
    this.radius = 0,
    this.placeholderIcon = Icons.home_repair_service,
  });
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: (url != null || id != null)
        ? Image.network(
            url ??
                'https://images.unsplash.com/$id?auto=format&fit=crop&w=500&q=80',
            width: width,
            height: height,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _placeholder(),
          )
        : _placeholder(),
  );

  Widget _placeholder() => Container(
    width: width,
    height: height,
    color: const Color(0xFFE4EDF7),
    child: Icon(placeholderIcon, color: blue),
  );
}

class ProviderDetailsScreen extends StatefulWidget {
  final NearbyProvider provider;
  final VoidCallback onRequest;
  const ProviderDetailsScreen({
    super.key,
    required this.provider,
    required this.onRequest,
  });
  @override
  State<ProviderDetailsScreen> createState() => _ProviderDetailsScreenState();
}

class _ProviderDetailsScreenState extends State<ProviderDetailsScreen> {
  int selected = 0;

  Future<void> _launch(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: CenteredMaxWidth(
      maxWidth: 820,
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Photo(
                          url: widget.provider.imageUrl,
                          width: double.infinity,
                          height: 220,
                        ),
                        Positioned(
                          top: 12,
                          left: 12,
                          child: CircleIcon(
                            onTap: () => Navigator.pop(context),
                            icon: Icons.arrow_back,
                          ),
                        ),
                        Positioned(
                          left: 20,
                          bottom: -45,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const CircleAvatar(
                              radius: 40,
                              backgroundColor: Color(0xFFE5F0FF),
                              child: Icon(Icons.person, size: 40, color: blue),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 55, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.provider.name,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: ink,
                                  ),
                                ),
                              ),
                              if (widget.provider.isVerified)
                                const Icon(Icons.verified, color: blue),
                            ],
                          ),
                          const SizedBox(height: 9),
                          Row(
                            children: [
                              if (widget.provider.rating != null) ...[
                                const Icon(
                                  Icons.star_rounded,
                                  color: Color(0xFFFFB547),
                                  size: 18,
                                ),
                                Text(
                                  ' ${widget.provider.rating}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (widget.provider.reviewCount != null)
                                  Text(
                                    '  (${widget.provider.reviewCount} reviews)',
                                    style: const TextStyle(
                                      color: muted,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                              if (widget.provider.rating != null)
                                const SizedBox(width: 8),
                              Text(
                                '${widget.provider.distanceKm.toStringAsFixed(1)} km away',
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          if (widget.provider.address.isNotEmpty)
                            Text(
                              widget.provider.address,
                              style: const TextStyle(
                                color: muted,
                                fontSize: 12,
                              ),
                            ),
                          if (widget.provider.phone != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                widget.provider.phone!,
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          if (widget.provider.source == 'osm')
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Text(
                                '© OpenStreetMap contributors',
                                style: TextStyle(color: muted, fontSize: 10),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Row(
                      children: [
                        tabItem(0, 'About'),
                        tabItem(1, 'Reviews'),
                        tabItem(2, 'Services'),
                      ],
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.all(20),
                    sliver: SliverToBoxAdapter(
                      child: selected == 0
                          ? aboutContent()
                          : selected == 1
                          ? reviewsContent()
                          : servicesContent(),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
              child: Row(
                children: [
                  if (widget.provider.phone != null) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _launch(
                          Uri(scheme: 'tel', path: widget.provider.phone),
                        ),
                        icon: const Icon(Icons.call_outlined),
                        label: const Text('Call'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: blue,
                          minimumSize: const Size(0, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _launch(
                        Uri.https('www.google.com', '/maps/dir/', {
                          'api': '1',
                          'destination':
                              '${widget.provider.latitude},${widget.provider.longitude}',
                        }),
                      ),
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Map'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: blue,
                        minimumSize: const Size(0, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: widget.onRequest,
                      style: FilledButton.styleFrom(
                        backgroundColor: blue,
                        minimumSize: const Size(0, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      child: const Text('Request Service'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget tabItem(int index, String label) => Expanded(
    child: InkWell(
      onTap: () => setState(() => selected = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected == index ? blue : const Color(0xFFE6EAF0),
              width: selected == index ? 2 : 1,
            ),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected == index ? blue : muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    ),
  );
  Widget aboutContent() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'About this provider',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: ink),
      ),
      const SizedBox(height: 9),
      Text(
        widget.provider.description.isEmpty
            ? 'No provider description is available.'
            : widget.provider.description,
        style: const TextStyle(height: 1.5, color: muted, fontSize: 13),
      ),
      const SizedBox(height: 20),
      Wrap(
        spacing: 9,
        runSpacing: 9,
        children:
            [
                  if (widget.provider.price != null) widget.provider.price!,
                  if (widget.provider.rating != null)
                    '${widget.provider.rating} rating${widget.provider.reviewCount == null ? '' : ' · ${widget.provider.reviewCount} reviews'}',
                  widget.provider.category,
                  if (widget.provider.isVerified) 'Verified provider',
                ]
                .map(
                  (s) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      s,
                      style: const TextStyle(
                        color: ink,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
                .toList(),
      ),
    ],
  );
  Widget reviewsContent() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Customer reviews',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ink),
      ),
      const SizedBox(height: 14),
      Text(
        widget.provider.reviewCount == null
            ? 'Review details are not available.'
            : '${widget.provider.reviewCount} reviews · average ${widget.provider.rating ?? 'unrated'}',
        style: const TextStyle(color: muted),
      ),
    ],
  );
  Widget servicesContent() => Column(
    children:
        [
              ...(categoryServices[widget.provider.category] ??
                  ['General Service']),
              ...([]),
            ]
            .map(
              (s) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle_outline, color: blue),
                title: Text(
                  s,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right, color: muted),
              ),
            )
            .toList(),
  );
}

class Review extends StatelessWidget {
  final String name, text;
  const Review({super.key, required this.name, required this.text});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.w700, color: ink),
              ),
            ),
            const Text('★★★★★', style: TextStyle(color: Color(0xFFFFB547))),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          text,
          style: const TextStyle(color: muted, fontSize: 12, height: 1.4),
        ),
      ],
    ),
  );
}

class CircleIcon extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  const CircleIcon({super.key, required this.onTap, required this.icon});
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: const CircleBorder(),
    child: IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: ink),
    ),
  );
}

class RequestServiceScreen extends StatefulWidget {
  final Future<ServiceRequest> Function(ServiceRequest) onSubmit;
  final NearbyProvider provider;
  final LocationService locations;
  const RequestServiceScreen({
    super.key,
    required this.provider,
    required this.onSubmit,
    required this.locations,
  });
  @override
  State<RequestServiceScreen> createState() => _RequestServiceScreenState();
}

class _RequestServiceScreenState extends State<RequestServiceScreen> {
  final form = GlobalKey<FormState>();
  final issue = TextEditingController();
  late String service =
      categoryServices[widget.provider.category]?.first ?? 'General Service';
  String get location => widget.locations.selected?.formattedAddress ?? '';
  DateTime? date;
  TimeOfDay? time;
  bool submitting = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Request Service',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    body: CenteredMaxWidth(
      maxWidth: 720,
      child: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Color(0xFFE5F0FF),
                    child: Icon(
                      serviceIcon(widget.provider.category),
                      color: blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.provider.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '⭐ ${widget.provider.rating ?? 'Unrated'}${widget.provider.reviewCount == null ? '' : ' · ${widget.provider.reviewCount} reviews'}  ·  ${widget.provider.category}',
                          style: TextStyle(fontSize: 11, color: muted),
                        ),
                      ],
                    ),
                  ),
                  if (widget.provider.isVerified)
                    const Icon(Icons.verified, color: blue),
                ],
              ),
            ),
            const SizedBox(height: 22),
            fieldLabel('Service Required'),
            DropdownButtonFormField<String>(
              initialValue: service,
              decoration: inputDecoration('Select a service'),
              items: [
                ...(categoryServices[widget.provider.category] ??
                    ['General Service']),
              ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() => service = v ?? service),
            ),
            const SizedBox(height: 18),
            fieldLabel('Describe the Issue'),
            TextFormField(
              controller: issue,
              maxLines: 4,
              decoration: inputDecoration('Tell us what needs to be fixed...'),
              validator: (s) => (s == null || s.trim().isEmpty)
                  ? 'Please describe the issue'
                  : null,
            ),
            const SizedBox(height: 18),
            fieldLabel('Preferred Date'),
            OutlinedButton.icon(
              onPressed: () async {
                final v = await showDatePicker(
                  context: context,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 180)),
                  initialDate: DateTime.now(),
                );
                if (v != null) setState(() => date = v);
              },
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(
                date == null
                    ? 'Choose a date'
                    : '${date!.day}/${date!.month}/${date!.year}',
              ),
              style: pickerStyle(),
            ),
            const SizedBox(height: 18),
            fieldLabel('Preferred Time'),
            OutlinedButton.icon(
              onPressed: () async {
                final v = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.now(),
                );
                if (v != null) setState(() => time = v);
              },
              icon: const Icon(Icons.schedule_outlined),
              label: Text(time?.format(context) ?? 'Choose a time'),
              style: pickerStyle(),
            ),
            const SizedBox(height: 18),
            fieldLabel('Location'),
            LocationSelector(locations: widget.locations),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: submit,
              style: FilledButton.styleFrom(
                backgroundColor: blue,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Submit Request',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ],
        ),
      ),
    ),
  );
  Future<void> submit() async {
    if (submitting) return;
    if (!form.currentState!.validate()) return;
    if (location.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose a saved or current location first.'),
        ),
      );
      return;
    }
    final r = ServiceRequest(
      service,
      issue.text.trim(),
      date == null ? 'Flexible' : '${date!.day}/${date!.month}/${date!.year}',
      time?.format(context) ?? 'Flexible',
      location,
      providerName: widget.provider.name,
      category: widget.provider.category,
    );
    setState(() => submitting = true);
    try {
      await widget.onSubmit(r);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not submit request: $error')),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => submitting = false);
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.check_circle,
          color: Color(0xFF28A875),
          size: 46,
        ),
        title: const Text('Request submitted'),
        content: Text('${widget.provider.name} will get back to you shortly.'),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  InputDecoration inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: Color(0xFFE7ECF2)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: Color(0xFFE7ECF2)),
    ),
  );
  ButtonStyle pickerStyle() => OutlinedButton.styleFrom(
    alignment: Alignment.centerLeft,
    minimumSize: const Size.fromHeight(50),
    foregroundColor: ink,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
    side: const BorderSide(color: Color(0xFFE7ECF2)),
  );
  Widget fieldLabel(String s) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      s,
      style: const TextStyle(
        color: ink,
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
    ),
  );
}

class RequestsScreen extends StatefulWidget {
  final List<ServiceRequest> requests;
  final Future<void> Function(ServiceRequest) onCancel;
  const RequestsScreen({
    super.key,
    required this.requests,
    required this.onCancel,
  });
  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  @override
  Widget build(BuildContext context) => CenteredMaxWidth(
    maxWidth: 860,
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 5),
            child: Text(
              'My Requests',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Track your local service bookings',
              style: TextStyle(color: muted, fontSize: 13),
            ),
          ),
          Expanded(
            child: widget.requests.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.assignment_outlined,
                          size: 55,
                          color: Color(0xFFAAB9CA),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'No requests yet',
                          style: TextStyle(
                            color: ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'Your service bookings will appear here',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: widget.requests.length,
                    itemBuilder: (context, i) {
                      final r = widget.requests[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    r.service,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: ink,
                                    ),
                                  ),
                                ),
                                if (r.status == 'Pending')
                                  PopupMenuButton<String>(
                                    tooltip: 'Request actions',
                                    onSelected: (value) async {
                                      if (value == 'cancel') {
                                        try {
                                          await widget.onCancel(r);
                                        } catch (error) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Could not cancel request: $error',
                                                ),
                                              ),
                                            );
                                          }
                                        }
                                      }
                                    },
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(
                                        value: 'cancel',
                                        child: Text('Cancel request'),
                                      ),
                                    ],
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE9F3FF),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              r.status,
                                              style: const TextStyle(
                                                color: blue,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 11,
                                              ),
                                            ),
                                            const Icon(
                                              Icons.arrow_drop_down,
                                              size: 16,
                                              color: blue,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: lightBlue,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 7,
                                      ),
                                      child: Text(
                                        r.status,
                                        style: const TextStyle(
                                          color: blue,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ),
                                IconButton(
                                  onPressed: () => showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: Text(r.service),
                                      content: Text(
                                        'Provider: ${r.providerName}\nCategory: ${r.category}\nDate: ${r.date}\nTime: ${r.time}\nLocation: ${r.location}\nStatus: ${r.status}\n\nIssue: ${r.issue}',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx),
                                          child: const Text('Close'),
                                        ),
                                      ],
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.info_outline,
                                    color: blue,
                                    size: 20,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '${r.providerName} · ${r.category}',
                              style: const TextStyle(
                                color: muted,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              r.issue,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: muted,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '${r.date} · ${r.time}  |  ${r.location}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}

class ProfileScreen extends StatefulWidget {
  final String userName, email;
  final Future<void> Function() onLogout;
  final Future<void> Function(String, String) onSaveProfile;
  final LocationService locations;
  const ProfileScreen({
    super.key,
    required this.userName,
    required this.email,
    required this.onLogout,
    required this.onSaveProfile,
    required this.locations,
  });
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool notifications = true;
  @override
  Widget build(BuildContext context) => CenteredMaxWidth(
    maxWidth: 720,
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Profile',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: navy,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 29,
                  backgroundColor: Colors.white24,
                  child: Text(
                    widget.userName.isEmpty
                        ? '?'
                        : widget.userName[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 22),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.userName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.email,
                        style: const TextStyle(
                          color: Color(0xFFC5D4E5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _item('My Profile', Icons.person_outline, _editProfile),
          _item('Saved Addresses', Icons.location_on_outlined, _addresses),
          _item(
            'My Service Requests',
            Icons.assignment_outlined,
            () => showDialog(
              context: context,
              builder: (c) => const AlertDialog(
                title: Text('Service requests'),
                content: Text('Use the Requests tab to review your bookings.'),
              ),
            ),
          ),
          _item('Help & Support', Icons.help_outline, _support),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.notifications_none, color: blue),
            title: const Text(
              'Notifications',
              style: TextStyle(color: ink, fontWeight: FontWeight.w600),
            ),
            value: notifications,
            onChanged: (v) => setState(() => notifications = v),
          ),
          _item(
            'Change Password',
            Icons.lock_outline,
            () => _simpleForm('Change Password', [
              'Current password',
              'New password',
              'Confirm new password',
            ]),
          ),
          _item(
            'Privacy Policy',
            Icons.privacy_tip_outlined,
            () => _info(
              'Privacy Policy',
              'Privacy controls and account data access require the service backend, which is not configured in this project.',
            ),
          ),
          _item(
            'Terms and Conditions',
            Icons.description_outlined,
            () => _info(
              'Terms and Conditions',
              'Local Services Finder helps customers discover independent service providers. Booking terms and provider policies should be supplied by the platform operator.',
            ),
          ),
          _item(
            'About Application',
            Icons.info_outline,
            () => _info(
              'About Local Services Finder',
              'Find trusted local service providers near you.',
            ),
          ),
          _item(
            'Logout',
            Icons.logout,
            _confirmLogout,
            color: Colors.redAccent,
          ),
        ],
      ),
    ),
  );
  Widget _item(
    String title,
    IconData icon,
    VoidCallback action, {
    Color color = blue,
  }) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 3),
    leading: Icon(icon, color: color),
    title: Text(
      title,
      style: TextStyle(
        color: color == blue ? ink : color,
        fontWeight: FontWeight.w600,
      ),
    ),
    trailing: const Icon(Icons.chevron_right, color: muted),
    onTap: action,
  );
  Future<void> _editProfile() async {
    final n = TextEditingController(text: widget.userName),
        e = TextEditingController(text: widget.email);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Edit profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: n,
              decoration: const InputDecoration(labelText: 'Full name'),
            ),
            TextField(
              controller: e,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true && n.text.trim().isNotEmpty && e.text.trim().isNotEmpty) {
      await widget.onSaveProfile(n.text.trim(), e.text.trim());
    }
  }

  Future<void> _addresses() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SavedAddressesScreen(locations: widget.locations),
      ),
    );
  }

  void _support() => _simpleForm('Contact Support', [
    'Subject',
    'Issue category',
    'Describe the issue',
  ]);
  Future<void> _simpleForm(String title, List<String> fields) async {
    final controllers = fields.map((_) => TextEditingController()).toList();
    final sent = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
              fields.length,
              (i) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: controllers[i],
                  obscureText: fields[i].toLowerCase().contains('password'),
                  maxLines: fields[i].toLowerCase().contains('describe')
                      ? 3
                      : 1,
                  decoration: InputDecoration(labelText: fields[i]),
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$title could not be saved because the backend is not configured.',
          ),
        ),
      );
    }
  }

  void _info(String title, String content) => showDialog(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Close'),
        ),
      ],
    ),
  );
  Future<void> _confirmLogout() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You will need to sign in again to access your account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (yes == true) await widget.onLogout();
  }
}

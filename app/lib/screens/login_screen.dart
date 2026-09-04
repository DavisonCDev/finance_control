import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'main_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isLogin = true;
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();

    final path = _isLogin ? '/auth/login' : '/auth/register';
    final body = _isLogin
        ? {'email': email, 'password': password}
        : {'name': name, 'email': email, 'password': password};

    final response = await ApiService.post(path, body);
    final data = ApiService.decode(response);

    if (response.statusCode == 200 || response.statusCode == 201) {
      await ApiService.saveToken(data['token']);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
      }
    } else {
      setState(() {
        _error = data['error'] ?? 'Erro desconhecido';
      });
    }

    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.account_balance, size: 72, color: Color(0xFF0D47A1)),
                const SizedBox(height: 16),
                Text(
                  'Finance Control',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 32),
                if (!_isLogin)
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Nome', prefixIcon: Icon(Icons.person)),
                  ),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.email)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Senha', prefixIcon: Icon(Icons.lock)),
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_isLogin ? 'Entrar' : 'Cadastrar'),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => setState(() => _isLogin = !_isLogin),
                  child: Text(_isLogin ? 'Criar conta' : 'Já tenho conta'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

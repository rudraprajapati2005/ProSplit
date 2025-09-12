import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/auth_repository.dart';
import '../domain/user_model.dart';

final authControllerProvider = StateNotifierProvider<AuthController, AsyncValue<UserModel?>>((ref) {
  return AuthController(ref.watch(authRepositoryProvider));
});

class AuthController extends StateNotifier<AsyncValue<UserModel?>> {
  final AuthRepository _authRepository;

  AuthController(this._authRepository) : super(const AsyncValue.loading()) {
    _authRepository.authStateChanges().listen((user) {
      if (user == null) {
        state = const AsyncValue.data(null);
      } else {
        _loadUser();
      }
    });
  }

  Future<void> _loadUser() async {
    print('🔄 AuthController: Starting _loadUser...');
    try {
      print('👤 AuthController: Getting current user from repository...');
      final user = await _authRepository.getCurrentUser();
      
      if (user != null) {
        print('✅ AuthController: User loaded: ${user.name} (${user.email})');
        state = AsyncValue.data(user);
      } else {
        // If Firestore is offline but user is authenticated, create basic user model
        print('⚠️ AuthController: Firestore offline, creating basic user model from Firebase Auth...');
        final firebaseUser = _authRepository.currentFirebaseUser;
        if (firebaseUser != null) {
          final basicUser = UserModel(
            id: firebaseUser.uid,
            email: firebaseUser.email ?? '',
            name: firebaseUser.displayName ?? 'User',
          );
          print('✅ AuthController: Basic user model created: ${basicUser.name} (${basicUser.email})');
          state = AsyncValue.data(basicUser);
        } else {
          print('❌ AuthController: No Firebase user found');
          state = const AsyncValue.data(null);
        }
      }
    } catch (e, st) {
      print('❌ AuthController: Error loading user: $e');
      print('❌ AuthController: Stack trace: $st');
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> _loadUserForAuth() async {
    print('🔄 AuthController: Starting _loadUserForAuth...');
    try {
      print('👤 AuthController: Getting current user from repository...');
      final user = await _authRepository.getCurrentUser();
      
      if (user != null) {
        print('✅ AuthController: User loaded: ${user.name} (${user.email})');
        state = AsyncValue.data(user);
      } else {
        // If Firestore is offline but user is authenticated, create basic user model
        print('⚠️ AuthController: Firestore offline, creating basic user model from Firebase Auth...');
        final firebaseUser = _authRepository.currentFirebaseUser;
        if (firebaseUser != null) {
          final basicUser = UserModel(
            id: firebaseUser.uid,
            email: firebaseUser.email ?? '',
            name: firebaseUser.displayName ?? 'User',
          );
          print('✅ AuthController: Basic user model created: ${basicUser.name} (${basicUser.email})');
          state = AsyncValue.data(basicUser);
        } else {
          print('❌ AuthController: No Firebase user found');
          state = const AsyncValue.data(null);
        }
      }
    } catch (e, st) {
      print('❌ AuthController: Error loading user: $e');
      print('❌ AuthController: Stack trace: $st');
      // Don't set error state during auth - let the UI handle it
      state = const AsyncValue.data(null);
      rethrow;
    }
  }

  Future<void> signIn(String email, String password) async {
    try {
      state = const AsyncValue.loading();
      await _authRepository.signInWithEmailAndPassword(email, password);
      await _loadUserForAuth();
    } catch (e, st) {
      // Don't set error state - let the UI handle the error
      // Reset to null state so the wrapper shows login screen
      state = const AsyncValue.data(null);
      rethrow; // Re-throw the error so the UI can catch it
    }
  }

  Future<void> signUp(String email, String password, String name) async {
    print('🚀 AuthController: Starting signUp process...');
    try {
      print('⏳ AuthController: Setting loading state...');
      state = const AsyncValue.loading();
      print('🔐 AuthController: Calling repository createUserWithEmailAndPassword...');
      await _authRepository.createUserWithEmailAndPassword(email, password, name);
      print('✅ AuthController: User creation completed, loading user profile...');
      await _loadUserForAuth();
      print('✅ AuthController: SignUp process completed successfully');
    } catch (e, st) {
      print('❌ AuthController: Error during signUp: $e');
      print('❌ AuthController: Stack trace: $st');
      
      // Provide more specific error messages
      String errorMessage = 'Sign up failed. Please try again.';
      if (e.toString().contains('network-request-failed')) {
        errorMessage = 'Network error. Please check your internet connection and try again.';
      } else if (e.toString().contains('email-already-in-use')) {
        errorMessage = 'This email is already registered. Please use a different email.';
      } else if (e.toString().contains('weak-password')) {
        errorMessage = 'Password is too weak. Please use a stronger password.';
      } else if (e.toString().contains('invalid-email')) {
        errorMessage = 'Please enter a valid email address.';
      }
      
      // Don't set error state - let the UI handle the error
      // Reset to null state so the wrapper shows login screen
      state = const AsyncValue.data(null);
      throw Exception(errorMessage);
    }
  }

  Future<void> signOut() async {
    try {
      await _authRepository.signOut();
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> updateProfile(UserModel user) async {
    try {
      await _authRepository.updateUserProfile(user);
      state = AsyncValue.data(user);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

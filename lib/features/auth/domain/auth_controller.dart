import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/auth_repository.dart';
import '../domain/user_model.dart';
import '../../../notifications/notification_service.dart';

final authControllerProvider = StateNotifierProvider<AuthController, AsyncValue<UserModel?>>((ref) {
  return AuthController(ref.watch(authRepositoryProvider));
});

class AuthController extends StateNotifier<AsyncValue<UserModel?>> {
  final AuthRepository _authRepository;

  AuthController(this._authRepository) : super(const AsyncValue.loading()) {
    _authRepository.authStateChanges().listen((user) {
      if (user == null) {
        state = const AsyncValue.data(null);
        // Stop per-user notification listener on sign-out
        NotificationService.instance.stopUserNotificationListener();
      } else {
        _loadUser();
        // Initialize notifications and sync token
        NotificationService.instance.init();
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
        // Sync FCM token under this user
        await NotificationService.instance.syncFcmToken(user.id);
        // Start per-user notification listener
        await NotificationService.instance.startUserNotificationListener(user.id);
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
      // Do NOT set global loading state; let the UI show local loading to avoid tree rebuild losing errors
      await _authRepository.signInWithEmailAndPassword(email, password);
      await _loadUserForAuth();
    } catch (e, st) {
      // Keep current state (likely null) so login screen persists and can show error
      rethrow; // Re-throw the error so the UI can catch it
    }
  }

  Future<void> _loadUserForAuth() async {
    try {
      final user = await _authRepository.getCurrentUser();
      state = AsyncValue.data(user);
    } catch (e) {
      state = const AsyncValue.data(null);
      rethrow;
    }
  }

  Future<void> signUp(String email, String password, String name) async {
    print('🚀 AuthController: Starting signUp process...');
    try {
      print('🔐 AuthController: Calling repository createUserWithEmailAndPassword...');
      await _authRepository.createUserWithEmailAndPassword(email, password, name);
      print('✅ AuthController: User creation completed, loading user profile...');
      await _loadUserForAuth();
      print('✅ AuthController: SignUp process completed successfully');
    } catch (e, st) {
      print('❌ AuthController: Error during signUp: $e');
      print('❌ AuthController: Stack trace: $st');
      // Keep state unchanged so signup screen can show the error
      rethrow; // Re-throw the original error so the UI can handle it properly
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

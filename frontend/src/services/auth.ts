import { Amplify } from "aws-amplify";
import {
  signIn as amplifySignIn,
  signUp as amplifySignUp,
  confirmSignUp as amplifyConfirmSignUp,
  signOut as amplifySignOut,
  getCurrentUser as amplifyGetCurrentUser,
  fetchAuthSession,
} from "aws-amplify/auth";

// ---------------------------------------------------------------------------
// Amplify configuration - reads Cognito settings from environment variables
// ---------------------------------------------------------------------------

Amplify.configure({
  Auth: {
    Cognito: {
      userPoolId: process.env.REACT_APP_COGNITO_USER_POOL_ID || "",
      userPoolClientId: process.env.REACT_APP_COGNITO_CLIENT_ID || "",
    },
  },
});

// ---------------------------------------------------------------------------
// Public auth helper functions
// ---------------------------------------------------------------------------

/**
 * Sign in an existing user with email (as username) and password.
 */
export async function signIn(
  email: string,
  password: string
): Promise<{ isSignedIn: boolean; nextStep?: unknown }> {
  const result = await amplifySignIn({ username: email, password });
  return {
    isSignedIn: result.isSignedIn,
    nextStep: result.nextStep,
  };
}

/**
 * Register a new user account.
 */
export async function signUp(
  email: string,
  password: string,
  name: string
): Promise<{ isSignUpComplete: boolean; nextStep?: unknown }> {
  const result = await amplifySignUp({
    username: email,
    password,
    options: {
      userAttributes: {
        email,
        name,
      },
    },
  });
  return {
    isSignUpComplete: result.isSignUpComplete,
    nextStep: result.nextStep,
  };
}

/**
 * Confirm a newly-registered account with the verification code sent to the
 * user's email.
 */
export async function confirmSignUp(
  email: string,
  code: string
): Promise<{ isSignUpComplete: boolean; nextStep?: unknown }> {
  const result = await amplifyConfirmSignUp({
    username: email,
    confirmationCode: code,
  });
  return {
    isSignUpComplete: result.isSignUpComplete,
    nextStep: result.nextStep,
  };
}

/**
 * Sign the current user out globally (invalidates all sessions).
 */
export async function signOut(): Promise<void> {
  await amplifySignOut({ global: true });
}

/**
 * Return the currently-authenticated user or null if nobody is signed in.
 */
export async function getCurrentUser(): Promise<{
  userId: string;
  username: string;
} | null> {
  try {
    const user = await amplifyGetCurrentUser();
    return { userId: user.userId, username: user.username };
  } catch {
    return null;
  }
}

/**
 * Retrieve the JWT id-token for the current session. Returns an empty string
 * when the user is not authenticated.
 */
export async function getAuthToken(): Promise<string> {
  try {
    const session = await fetchAuthSession();
    return session.tokens?.idToken?.toString() ?? "";
  } catch {
    return "";
  }
}

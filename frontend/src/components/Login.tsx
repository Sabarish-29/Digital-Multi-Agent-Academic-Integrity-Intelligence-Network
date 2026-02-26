import React, { useState } from "react";
import { useNavigate } from "react-router-dom";
import { toast } from "react-toastify";

import {
  signIn,
  signUp,
  confirmSignUp,
} from "../services/auth";
import { useAuth } from "../App";

// ---------------------------------------------------------------------------
// View modes
// ---------------------------------------------------------------------------

type ViewMode = "login" | "register" | "confirm";

// ---------------------------------------------------------------------------
// Login component
// ---------------------------------------------------------------------------

const Login: React.FC = () => {
  const navigate = useNavigate();
  const { refreshAuth } = useAuth();

  const [view, setView] = useState<ViewMode>("login");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  // Form fields
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [name, setName] = useState("");
  const [confirmCode, setConfirmCode] = useState("");

  // -----------------------------------------------------------------------
  // Handlers
  // -----------------------------------------------------------------------

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    setLoading(true);

    try {
      const result = await signIn(email, password);
      if (result.isSignedIn) {
        await refreshAuth();
        toast.success("Signed in successfully!");
        navigate("/dashboard", { replace: true });
      }
    } catch (err: unknown) {
      const message =
        err instanceof Error ? err.message : "Invalid credentials";
      setError(message);
    } finally {
      setLoading(false);
    }
  };

  const handleRegister = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");

    if (password !== confirmPassword) {
      setError("Passwords do not match.");
      return;
    }
    if (password.length < 8) {
      setError("Password must be at least 8 characters.");
      return;
    }

    setLoading(true);

    try {
      const result = await signUp(email, password, name);
      if (!result.isSignUpComplete) {
        setView("confirm");
        toast.info("A verification code has been sent to your email.");
      }
    } catch (err: unknown) {
      const message =
        err instanceof Error ? err.message : "Registration failed";
      setError(message);
    } finally {
      setLoading(false);
    }
  };

  const handleConfirm = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    setLoading(true);

    try {
      const result = await confirmSignUp(email, confirmCode);
      if (result.isSignUpComplete) {
        toast.success("Account confirmed! You can now sign in.");
        setView("login");
        setPassword("");
      }
    } catch (err: unknown) {
      const message =
        err instanceof Error ? err.message : "Confirmation failed";
      setError(message);
    } finally {
      setLoading(false);
    }
  };

  // -----------------------------------------------------------------------
  // Shared input styles
  // -----------------------------------------------------------------------

  const inputClass =
    "w-full px-4 py-2.5 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-navy-500 focus:border-navy-500 outline-none transition-colors placeholder-gray-400";

  const primaryBtn =
    "w-full py-2.5 px-4 bg-navy-700 hover:bg-navy-800 text-white text-sm font-medium rounded-lg transition-colors disabled:opacity-50 disabled:cursor-not-allowed";

  // -----------------------------------------------------------------------
  // Render
  // -----------------------------------------------------------------------

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-navy-800 via-navy-700 to-blue-900 px-4">
      <div className="w-full max-w-md">
        {/* Brand header */}
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-14 h-14 bg-blue-500 rounded-2xl mb-4 shadow-lg">
            <span className="text-white font-bold text-2xl">D</span>
          </div>
          <h1 className="text-2xl font-bold text-white tracking-wide">
            DMAIIN
          </h1>
          <p className="mt-1 text-navy-200 text-sm">
            Digital Multi-Agent Academic Integrity Intelligence Network
          </p>
        </div>

        {/* Card */}
        <div className="bg-white rounded-2xl shadow-xl p-8">
          {/* ------- LOGIN ------- */}
          {view === "login" && (
            <>
              <h2 className="text-xl font-semibold text-navy-800 mb-6">
                Sign in to your account
              </h2>

              {error && (
                <div className="mb-4 p-3 bg-red-50 border border-red-200 text-red-700 text-sm rounded-lg">
                  {error}
                </div>
              )}

              <form onSubmit={handleLogin} className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Email address
                  </label>
                  <input
                    type="email"
                    required
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    className={inputClass}
                    placeholder="you@university.edu"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Password
                  </label>
                  <input
                    type="password"
                    required
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    className={inputClass}
                    placeholder="Enter your password"
                  />
                </div>

                <button type="submit" disabled={loading} className={primaryBtn}>
                  {loading ? "Signing in..." : "Sign in"}
                </button>
              </form>

              <p className="mt-6 text-center text-sm text-gray-500">
                Don't have an account?{" "}
                <button
                  type="button"
                  onClick={() => {
                    setError("");
                    setView("register");
                  }}
                  className="text-navy-600 font-medium hover:text-navy-800 transition-colors"
                >
                  Create one
                </button>
              </p>
            </>
          )}

          {/* ------- REGISTER ------- */}
          {view === "register" && (
            <>
              <h2 className="text-xl font-semibold text-navy-800 mb-6">
                Create your account
              </h2>

              {error && (
                <div className="mb-4 p-3 bg-red-50 border border-red-200 text-red-700 text-sm rounded-lg">
                  {error}
                </div>
              )}

              <form onSubmit={handleRegister} className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Full name
                  </label>
                  <input
                    type="text"
                    required
                    value={name}
                    onChange={(e) => setName(e.target.value)}
                    className={inputClass}
                    placeholder="Jane Doe"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Email address
                  </label>
                  <input
                    type="email"
                    required
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    className={inputClass}
                    placeholder="you@university.edu"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Password
                  </label>
                  <input
                    type="password"
                    required
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    className={inputClass}
                    placeholder="Min. 8 characters"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Confirm password
                  </label>
                  <input
                    type="password"
                    required
                    value={confirmPassword}
                    onChange={(e) => setConfirmPassword(e.target.value)}
                    className={inputClass}
                    placeholder="Re-enter password"
                  />
                </div>

                <button type="submit" disabled={loading} className={primaryBtn}>
                  {loading ? "Creating account..." : "Create account"}
                </button>
              </form>

              <p className="mt-6 text-center text-sm text-gray-500">
                Already have an account?{" "}
                <button
                  type="button"
                  onClick={() => {
                    setError("");
                    setView("login");
                  }}
                  className="text-navy-600 font-medium hover:text-navy-800 transition-colors"
                >
                  Sign in
                </button>
              </p>
            </>
          )}

          {/* ------- CONFIRM ------- */}
          {view === "confirm" && (
            <>
              <h2 className="text-xl font-semibold text-navy-800 mb-2">
                Verify your email
              </h2>
              <p className="text-sm text-gray-500 mb-6">
                We sent a 6-digit code to{" "}
                <span className="font-medium text-gray-700">{email}</span>.
                Enter it below to activate your account.
              </p>

              {error && (
                <div className="mb-4 p-3 bg-red-50 border border-red-200 text-red-700 text-sm rounded-lg">
                  {error}
                </div>
              )}

              <form onSubmit={handleConfirm} className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Verification code
                  </label>
                  <input
                    type="text"
                    required
                    value={confirmCode}
                    onChange={(e) => setConfirmCode(e.target.value)}
                    className={inputClass}
                    placeholder="123456"
                    maxLength={6}
                  />
                </div>

                <button type="submit" disabled={loading} className={primaryBtn}>
                  {loading ? "Verifying..." : "Verify account"}
                </button>
              </form>

              <p className="mt-6 text-center text-sm text-gray-500">
                <button
                  type="button"
                  onClick={() => {
                    setError("");
                    setView("login");
                  }}
                  className="text-navy-600 font-medium hover:text-navy-800 transition-colors"
                >
                  Back to sign in
                </button>
              </p>
            </>
          )}
        </div>

        {/* Footer */}
        <p className="mt-6 text-center text-xs text-navy-300">
          DMAIIN &mdash; Academic Integrity Portal
        </p>
      </div>
    </div>
  );
};

export default Login;

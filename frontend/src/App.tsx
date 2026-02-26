import React, { createContext, useContext, useEffect, useState } from "react";
import { Routes, Route, Navigate } from "react-router-dom";
import { ToastContainer } from "react-toastify";
import "react-toastify/dist/ReactToastify.css";

import { getCurrentUser, signOut as authSignOut } from "./services/auth";
import Login from "./components/Login";
import FileUpload from "./components/FileUpload";
import SubmissionList from "./components/SubmissionList";

// ---------------------------------------------------------------------------
// Auth context
// ---------------------------------------------------------------------------

interface AuthState {
  isAuthenticated: boolean;
  userId: string;
  username: string;
}

interface AuthContextValue extends AuthState {
  /** Re-check authentication status from Amplify. */
  refreshAuth: () => Promise<void>;
  /** Sign the user out and reset local state. */
  handleSignOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue>({
  isAuthenticated: false,
  userId: "",
  username: "",
  refreshAuth: async () => {},
  handleSignOut: async () => {},
});

export const useAuth = (): AuthContextValue => useContext(AuthContext);

// ---------------------------------------------------------------------------
// Dashboard layout
// ---------------------------------------------------------------------------

const Dashboard: React.FC = () => {
  const { username, handleSignOut } = useAuth();

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Top navigation bar */}
      <nav className="bg-navy-800 shadow-lg">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between h-16">
            {/* Brand */}
            <div className="flex items-center space-x-3">
              <div className="w-8 h-8 bg-blue-500 rounded-lg flex items-center justify-center">
                <span className="text-white font-bold text-sm">D</span>
              </div>
              <span className="text-white font-semibold text-lg tracking-wide">
                DMAIIN
              </span>
              <span className="hidden sm:inline text-navy-300 text-sm">
                Academic Integrity Portal
              </span>
            </div>

            {/* User menu */}
            <div className="flex items-center space-x-4">
              <span className="text-navy-200 text-sm">
                Signed in as{" "}
                <span className="font-medium text-white">{username}</span>
              </span>
              <button
                onClick={handleSignOut}
                className="px-3 py-1.5 text-sm text-navy-200 hover:text-white border border-navy-600 hover:border-navy-400 rounded-md transition-colors"
              >
                Sign out
              </button>
            </div>
          </div>
        </div>
      </nav>

      {/* Main content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
          {/* Upload section */}
          <div className="lg:col-span-1">
            <FileUpload />
          </div>

          {/* Submissions table */}
          <div className="lg:col-span-2">
            <SubmissionList />
          </div>
        </div>
      </main>
    </div>
  );
};

// ---------------------------------------------------------------------------
// Protected route wrapper
// ---------------------------------------------------------------------------

const ProtectedRoute: React.FC<{ children: React.ReactNode }> = ({
  children,
}) => {
  const { isAuthenticated } = useAuth();
  if (!isAuthenticated) {
    return <Navigate to="/login" replace />;
  }
  return <>{children}</>;
};

// ---------------------------------------------------------------------------
// App root
// ---------------------------------------------------------------------------

const App: React.FC = () => {
  const [auth, setAuth] = useState<AuthState>({
    isAuthenticated: false,
    userId: "",
    username: "",
  });
  const [loading, setLoading] = useState(true);

  const refreshAuth = async () => {
    try {
      const user = await getCurrentUser();
      if (user) {
        setAuth({
          isAuthenticated: true,
          userId: user.userId,
          username: user.username,
        });
      } else {
        setAuth({ isAuthenticated: false, userId: "", username: "" });
      }
    } catch {
      setAuth({ isAuthenticated: false, userId: "", username: "" });
    }
  };

  const handleSignOut = async () => {
    await authSignOut();
    setAuth({ isAuthenticated: false, userId: "", username: "" });
  };

  useEffect(() => {
    refreshAuth().finally(() => setLoading(false));
  }, []);

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <div className="text-center space-y-4">
          <div className="w-12 h-12 border-4 border-navy-200 border-t-navy-700 rounded-full animate-spin mx-auto" />
          <p className="text-navy-600 text-sm font-medium">Loading...</p>
        </div>
      </div>
    );
  }

  return (
    <AuthContext.Provider value={{ ...auth, refreshAuth, handleSignOut }}>
      <Routes>
        {/* Public route */}
        <Route path="/login" element={<Login />} />

        {/* Protected route */}
        <Route
          path="/dashboard"
          element={
            <ProtectedRoute>
              <Dashboard />
            </ProtectedRoute>
          }
        />

        {/* Default redirect */}
        <Route
          path="*"
          element={
            <Navigate
              to={auth.isAuthenticated ? "/dashboard" : "/login"}
              replace
            />
          }
        />
      </Routes>

      <ToastContainer
        position="top-right"
        autoClose={4000}
        hideProgressBar={false}
        newestOnTop
        closeOnClick
        pauseOnFocusLoss
        draggable
        pauseOnHover
        theme="light"
      />
    </AuthContext.Provider>
  );
};

export default App;

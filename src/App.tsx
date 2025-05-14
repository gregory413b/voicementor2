import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import { useEffect, useState } from 'react';
import { supabase } from './lib/supabase';
import AuthLayout from './layouts/AuthLayout';
import AppLayout from './layouts/AppLayout';
import Login from './pages/auth/Login';
import Register from './pages/auth/Register';
import Dashboard from './pages/app/Dashboard';
import Messages from './pages/app/Messages';
import Profile from './pages/app/Profile';
import Contacts from './pages/app/Contacts';
import Loading from './components/ui/Loading';
import { useAuthStore } from './stores/authStore';

function App() {
  const [isLoading, setIsLoading] = useState(true);
  const { session, user, setSession, clearSession } = useAuthStore();
  
  useEffect(() => {
    // Check for existing session
    supabase.auth.getSession().then(({ data: { session } }) => {
      setSession(session);
      setIsLoading(false);
    });

    // Listen for auth changes
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      setSession(session);
    });

    return () => subscription.unsubscribe();
  }, [setSession]);

  if (isLoading) {
    return <Loading />;
  }

  return (
    <Router>
      <Routes>
        {/* Public Routes */}
        <Route element={<AuthLayout />}>
          <Route path="/login" element={!session ? <Login /> : <Navigate to="/dashboard" />} />
          <Route path="/register" element={!session ? <Register /> : <Navigate to="/dashboard" />} />
        </Route>

        {/* Protected Routes */}
        <Route element={<AppLayout />}>
          <Route path="/dashboard" element={session ? <Dashboard /> : <Navigate to="/login" />} />
          <Route path="/messages/:contactId" element={session ? <Messages /> : <Navigate to="/login" />} />
          <Route path="/profile" element={session ? <Profile /> : <Navigate to="/login" />} />
          <Route path="/contacts" element={session ? <Contacts /> : <Navigate to="/login" />} />
        </Route>

        {/* Default Route */}
        <Route path="*" element={<Navigate to={session ? "/dashboard" : "/login"} />} />
      </Routes>
    </Router>
  );
}

export default App
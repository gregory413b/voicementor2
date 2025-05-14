import { Outlet } from 'react-router-dom';
import { Square as MicSquare } from 'lucide-react';

const AuthLayout = () => {
  return (
    <div className="min-h-screen bg-gradient-to-br from-primary-900 to-secondary-900 flex flex-col items-center justify-center px-4 sm:px-6 lg:px-8">
      <div className="w-full max-w-md">
        <div className="text-center mb-8">
          <div className="flex justify-center">
            <MicSquare size={48} className="text-white" />
          </div>
          <h1 className="mt-4 text-3xl font-bold tracking-tight text-white">
            VoiceLink
          </h1>
          <p className="mt-2 text-sm text-gray-200">
            Tiered Voice Messaging Platform
          </p>
        </div>
        
        <div className="bg-white py-8 px-6 shadow rounded-lg">
          <Outlet />
        </div>
        
        <p className="mt-4 text-center text-sm text-gray-200">
          &copy; {new Date().getFullYear()} VoiceLink. All rights reserved.
        </p>
      </div>
    </div>
  );
};

export default AuthLayout;
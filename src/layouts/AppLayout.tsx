import { Outlet } from 'react-router-dom';
import BottomNav from '../components/navigation/BottomNav';

const AppLayout = () => {
  return (
    <div className="min-h-screen bg-gray-50">
      <main className="pb-20">
        <div className="py-6">
          <div className="mx-auto max-w-7xl px-4 sm:px-6 md:px-8">
            <Outlet />
          </div>
        </div>
      </main>
      <BottomNav />
    </div>
  );
};

export default AppLayout;
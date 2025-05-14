import { Loader2 } from 'lucide-react';

interface LoadingProps {
  size?: number;
  className?: string;
}

const Loading = ({ size = 24, className = '' }: LoadingProps) => {
  return (
    <div className={`flex items-center justify-center h-full w-full ${className}`}>
      <Loader2 size={size} className="animate-spin text-blue-700" />
    </div>
  );
};

export default Loading;
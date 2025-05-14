import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuthStore } from '../../stores/authStore';
import { supabase } from '../../lib/supabase';
import { formatDate } from '../../lib/utils';
import Loading from '../../components/ui/Loading';
import { MessageSquare, User, Volume2 } from 'lucide-react';

interface RecentMessage {
  id: string;
  created_at: string;
  audio_url: string | null;
  text_transcript: string | null;
  unread_count: number;
  sender: {
    id: string;
    full_name: string;
  };
  conversation: {
    id: string;
    client

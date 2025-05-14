import { useState, useRef, useEffect } from 'react';
import { Send, Mic, StopCircle, Trash2 } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { formatDuration } from '../../lib/utils';
import { useAuthStore } from '../../stores/authStore';
import Loading from '../ui/Loading';

interface MessageInputProps {
  conversationId: string;
  onMessageSent: () => void;
}

const MessageInput = ({ conversationId, onMessageSent }: MessageInputProps) => {
  const [text, setText] = useState('');
  const [isRecording, setIsRecording] = useState(false);
  const [recordingTime, setRecordingTime] = useState(0);
  const [audioBlob, setAudioBlob] = useState<Blob | null>(null);
  const [isSending, setIsSending] = useState(false);
  const mediaRecorderRef = useRef<MediaRecorder | null>(null);
  const audioChunksRef = useRef<Blob[]>([]);
  const timerRef = useRef<number | null>(null);
  const recordingTimeoutRef = useRef<number | null>(null);
  const { user } = useAuthStore();
  
  useEffect(() => {
    return () => {
      if (timerRef.current) {
        clearInterval(timerRef.current);
      }
      if (recordingTimeoutRef.current) {
        clearTimeout(recordingTimeoutRef.current);
      }
      if (mediaRecorderRef.current && isRecording) {
        mediaRecorderRef.current.stop();
      }
    };
  }, [isRecording]);
  
  const startRecording = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      
      const mediaRecorder = new MediaRecorder(stream);
      mediaRecorderRef.current = mediaRecorder;
      audioChunksRef.current = [];
      
      mediaRecorder.ondataavailable = (e) => {
        audioChunksRef.current.push(e.data);
      };
      
      mediaRecorder.onstop = () => {
        const audioBlob = new Blob(audioChunksRef.current, { type: 'audio/mp3' });
        setAudioBlob(audioBlob);
        
        // Stop all tracks in the stream to release the microphone
        stream.getTracks().forEach(track => track.stop());
      };
      
      // Start recording
      mediaRecorder.start();
      setIsRecording(true);
      setRecordingTime(0);
      
      // Start timer
      timerRef.current = window.setInterval(() => {
        setRecordingTime(prev => prev + 1);
      }, 1000);
      
      // Set 15-minute timeout
      recordingTimeoutRef.current = window.setTimeout(() => {
        stopRecording();
      }, 15 * 60 * 1000); // 15 minutes
      
    } catch (error) {
      console.error('Error accessing microphone:', error);
      alert('Could not access microphone. Please check permissions.');
    }
  };
  
  const stopRecording = () => {
    if (mediaRecorderRef.current && isRecording) {
      mediaRecorderRef.current.stop();
      setIsRecording(false);
      
      if (timerRef.current) {
        clearInterval(timerRef.current);
        timerRef.current = null;
      }
      
      if (recordingTimeoutRef.current) {
        clearTimeout(recordingTimeoutRef.current);
        recordingTimeoutRef.current = null;
      }
    }
  };
  
  const cancelRecording = () => {
    stopRecording();
    setAudioBlob(null);
    setRecordingTime(0);
  };
  
  const sendMessage = async () => {
    if ((!text && !audioBlob) || !user) return;
    
    setIsSending(true);
    
    try {
      if (audioBlob) {
        const messageId = crypto.randomUUID();
        const filePath = `${conversationId}/${messageId}.mp3`;
        
        // Upload the audio file
        const { error: uploadError } = await supabase.storage
          .from('voices')
          .upload(filePath, audioBlob, { contentType: 'audio/mp3' });
        
        if (uploadError) throw uploadError;
        
        // Create the message record
        const { error: messageError } = await supabase
          .from('audio_messages')
          .insert({
            id: messageId,
            conversation_id: conversationId,
            sender_id: user.id,
            audio_url: filePath,
            duration: recordingTime
          });
        
        if (messageError) throw messageError;
        
        // Clear the recorded audio
        setAudioBlob(null);
        setRecordingTime(0);
      } else if (text) {
        // Send text message
        const { error: messageError } = await supabase
          .from('audio_messages')
          .insert({
            conversation_id: conversationId,
            sender_id: user.id,
            text_transcript: text,
            duration: 0,
            audio_url: null
          });
        
        if (messageError) throw messageError;
        
        // Clear the text input
        setText('');
      }
      
      onMessageSent();
      
    } catch (error) {
      console.error('Error sending message:', error);
      alert('Failed to send message. Please try again.');
    } finally {
      setIsSending(false);
    }
  };
  
  return (
    <div className="border-t border-gray-200 bg-white px-4 py-3">
      <div className="flex items-center">
        {!isRecording && !audioBlob && (
          <>
            <input
              type="text"
              value={text}
              onChange={(e) => setText(e.target.value)}
              placeholder="Type a message..."
              className="flex-1 border-none focus:ring-0 focus:outline-none text-sm"
            />
            
            <button
              type="button"
              onClick={text ? sendMessage : startRecording}
              disabled={isSending}
              className="ml-2 inline-flex items-center rounded-full p-2 text-gray-400 hover:text-gray-600 focus:outline-none"
            >
              {text ? (
                <Send className="h-6 w-6" />
              ) : (
                <Mic className="h-6 w-6" />
              )}
            </button>
          </>
        )}
        
        {isRecording && (
          <div className="flex-1 flex items-center justify-between">
            <div className="flex items-center">
              <div className="mr-3 h-3 w-3 rounded-full bg-error-500 animate-recording-pulse" />
              <span className="text-sm font-medium text-gray-700">
                {formatDuration(recordingTime)}
              </span>
            </div>
            
            <button
              type="button"
              onClick={stopRecording}
              className="inline-flex items-center rounded-full bg-error-500 p-2 text-white shadow-sm hover:bg-error-600 focus:outline-none"
            >
              <StopCircle className="h-6 w-6" />
            </button>
          </div>
        )}
        
        {!isRecording && audioBlob && (
          <div className="flex-1 flex items-center justify-between">
            <div className="flex items-center space-x-4">
              <div className="text-sm font-medium text-gray-700">
                {formatDuration(recordingTime)}
              </div>
              
              <button
                type="button"
                onClick={cancelRecording}
                className="inline-flex items-center text-gray-500 hover:text-gray-700"
              >
                <Trash2 className="h-5 w-5" />
              </button>
            </div>
            
            <button
              type="button"
              onClick={sendMessage}
              disabled={isSending}
              className="inline-flex items-center rounded-full bg-primary-600 p-2 text-white shadow-sm hover:bg-primary-700 focus:outline-none disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {isSending ? <Loading size={20} className="m-0" /> : <Send className="h-6 w-6" />}
            </button>
          </div>
        )}
      </div>
    </div>
  );
};

export default MessageInput;
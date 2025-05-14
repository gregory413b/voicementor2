import { useState, useRef, useEffect } from 'react';
import { Mic, StopCircle, Trash2, Send } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { formatDuration } from '../../lib/utils';
import { useAuthStore } from '../../stores/authStore';
import Loading from '../ui/Loading';

interface AudioRecorderProps {
  conversationId: string;
  onMessageSent: () => void;
}

const AudioRecorder = ({ conversationId, onMessageSent }: AudioRecorderProps) => {
  const [isRecording, setIsRecording] = useState(false);
  const [recordingTime, setRecordingTime] = useState(0);
  const [audioBlob, setAudioBlob] = useState<Blob | null>(null);
  const [isSending, setIsSending] = useState(false);
  
  const mediaRecorderRef = useRef<MediaRecorder | null>(null);
  const audioContextRef = useRef<AudioContext | null>(null);
  const analyserRef = useRef<AnalyserNode | null>(null);
  const animationFrameRef = useRef<number | null>(null);
  const audioChunksRef = useRef<Blob[]>([]);
  const timerRef = useRef<number | null>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const startTimeRef = useRef<number>(0);
  const { user } = useAuthStore();
  
  useEffect(() => {
    return () => {
      if (timerRef.current) {
        clearInterval(timerRef.current);
      }
      
      if (mediaRecorderRef.current && isRecording) {
        mediaRecorderRef.current.stop();
      }
      
      if (animationFrameRef.current) {
        cancelAnimationFrame(animationFrameRef.current);
      }
      
      if (audioContextRef.current) {
        audioContextRef.current.close();
      }
    };
  }, [isRecording]);
  
  const drawWaveform = () => {
    if (!canvasRef.current || !analyserRef.current) return;
    
    const canvas = canvasRef.current;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    
    // Set up canvas dimensions
    const dpr = window.devicePixelRatio || 1;
    const rect = canvas.getBoundingClientRect();
    canvas.width = rect.width * dpr;
    canvas.height = rect.height * dpr;
    ctx.scale(dpr, dpr);
    
    const analyser = analyserRef.current;
    const bufferLength = analyser.frequencyBinCount;
    const dataArray = new Uint8Array(bufferLength);
    
    const draw = () => {
      if (!isRecording) return;
      
      animationFrameRef.current = requestAnimationFrame(draw);
      analyser.getByteTimeDomainData(dataArray);
      
      // Clear canvas
      ctx.fillStyle = 'rgb(249, 250, 251)';
      ctx.fillRect(0, 0, rect.width, rect.height);
      
      // Draw waveform
      ctx.lineWidth = 2;
      ctx.strokeStyle = 'rgb(37, 99, 235)';
      ctx.beginPath();
      
      const sliceWidth = (rect.width * 1.0) / bufferLength;
      let x = 0;
      
      for (let i = 0; i < bufferLength; i++) {
        const v = dataArray[i] / 128.0;
        const y = (v * rect.height) / 2;
        
        if (i === 0) {
          ctx.moveTo(x, y);
        } else {
          ctx.lineTo(x, y);
        }
        
        x += sliceWidth;
      }
      
      ctx.lineTo(rect.width, rect.height / 2);
      ctx.stroke();
    };
    
    draw();
  };
  
  const updateTimer = () => {
    if (!startTimeRef.current) return;
    const currentTime = Date.now();
    const elapsedTime = Math.floor((currentTime - startTimeRef.current) / 1000);
    setRecordingTime(elapsedTime);
  };
  
  const startRecording = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      
      // Set up audio context and analyser
      const audioContext = new AudioContext();
      audioContextRef.current = audioContext;
      
      const analyser = audioContext.createAnalyser();
      analyserRef.current = analyser;
      analyser.fftSize = 2048;
      
      const source = audioContext.createMediaStreamSource(stream);
      source.connect(analyser);
      
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
        
        if (audioContextRef.current) {
          audioContextRef.current.close();
        }
      };
      
      // Start recording
      mediaRecorder.start();
      setIsRecording(true);
      setRecordingTime(0);
      startTimeRef.current = Date.now();
      
      // Start waveform visualization
      drawWaveform();
      
      // Start timer
      timerRef.current = window.setInterval(updateTimer, 1000);
      
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
      
      if (animationFrameRef.current) {
        cancelAnimationFrame(animationFrameRef.current);
        animationFrameRef.current = null;
      }
    }
  };
  
  const cancelRecording = () => {
    stopRecording();
    setAudioBlob(null);
    setRecordingTime(0);
  };
  
  const sendVoiceMessage = async () => {
    if (!audioBlob || !user) return;
    
    setIsSending(true);
    
    try {
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
      onMessageSent();
      
    } catch (error) {
      console.error('Error sending voice message:', error);
      alert('Failed to send message. Please try again.');
    } finally {
      setIsSending(false);
    }
  };
  
  return (
    <div className="border-t border-gray-200 bg-white px-4 py-3">
      <div className="flex items-center">
        {!isRecording && !audioBlob && (
          <div className="flex-1 flex justify-center">
            <button
              type="button"
              onClick={startRecording}
              className="inline-flex items-center rounded-full bg-primary-600 p-3 text-white shadow-sm hover:bg-primary-700 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:ring-offset-2"
            >
              <Mic className="h-5 w-5" />
              <span className="sr-only">Start recording</span>
            </button>
          </div>
        )}
        
        {isRecording && (
          <div className="flex-1 flex items-center justify-between">
            <div className="flex-1">
              <div className="flex items-center mb-2">
                <div className="mr-3 h-3 w-3 rounded-full bg-error-500 animate-recording-pulse" />
                <span className="text-sm font-medium text-gray-700">
                  {formatDuration(recordingTime)}
                </span>
              </div>
              
              <canvas
                ref={canvasRef}
                className="w-full h-12 bg-gray-50 rounded-lg"
                style={{ width: '100%', height: '48px' }}
              />
            </div>
            
            <button
              type="button"
              onClick={stopRecording}
              className="ml-4 inline-flex items-center rounded-full bg-error-500 p-3 text-white shadow-sm hover:bg-error-600 focus:outline-none focus:ring-2 focus:ring-error-500 focus:ring-offset-2"
            >
              <StopCircle className="h-5 w-5" />
              <span className="sr-only">Stop recording</span>
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
                <span className="sr-only">Discard recording</span>
              </button>
            </div>
            
            <button
              type="button"
              onClick={sendVoiceMessage}
              disabled={isSending}
              className="inline-flex items-center rounded-full bg-primary-600 p-3 text-white shadow-sm hover:bg-primary-700 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:ring-offset-2 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {isSending ? <Loading size={20} className="m-0" /> : <Send className="h-5 w-5" />}
              <span className="sr-only">Send message</span>
            </button>
          </div>
        )}
      </div>
    </div>
  );
};

export default AudioRecorder;
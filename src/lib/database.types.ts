export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export interface Database {
  public: {
    Tables: {
      profiles: {
        Row: {
          id: string
          created_at: string
          role: 'client' | 'mentor' | 'training_director'
          mentor_id: string | null
          director_id: string | null
          full_name: string
          avatar_url: string | null
        }
        Insert: {
          id: string
          created_at?: string
          role: 'client' | 'mentor' | 'training_director'
          mentor_id?: string | null
          director_id?: string | null
          full_name: string
          avatar_url?: string | null
        }
        Update: {
          id?: string
          created_at?: string
          role?: 'client' | 'mentor' | 'training_director'
          mentor_id?: string | null
          director_id?: string | null
          full_name?: string
          avatar_url?: string | null
        }
      }
      conversations: {
        Row: {
          id: string
          created_at: string
          client_id: string
          mentor_id: string
        }
        Insert: {
          id?: string
          created_at?: string
          client_id: string
          mentor_id: string
        }
        Update: {
          id?: string
          created_at?: string
          client_id?: string
          mentor_id?: string
        }
      }
      conversation_participants: {
        Row: {
          conversation_id: string
          user_id: string
          role: 'client' | 'mentor' | 'training_director'
        }
        Insert: {
          conversation_id: string
          user_id: string
          role: 'client' | 'mentor' | 'training_director'
        }
        Update: {
          conversation_id?: string
          user_id?: string
          role?: 'client' | 'mentor' | 'training_director'
        }
      }
      audio_messages: {
        Row: {
          id: string
          created_at: string
          conversation_id: string
          sender_id: string
          audio_url: string
          duration: number
          text_transcript: string | null
        }
        Insert: {
          id?: string
          created_at?: string
          conversation_id: string
          sender_id: string
          audio_url: string
          duration: number
          text_transcript?: string | null
        }
        Update: {
          id?: string
          created_at?: string
          conversation_id?: string
          sender_id?: string
          audio_url?: string
          duration?: number
          text_transcript?: string | null
        }
      }
      bookmarks: {
        Row: {
          id: string
          created_at: string
          message_id: string
          user_id: string
          timestamp_sec: number
          label: string
        }
        Insert: {
          id?: string
          created_at?: string
          message_id: string
          user_id: string
          timestamp_sec: number
          label: string
        }
        Update: {
          id?: string
          created_at?: string
          message_id?: string
          user_id?: string
          timestamp_sec?: number
          label?: string
        }
      }
      favorites: {
        Row: {
          user_id: string
          message_id: string
          created_at: string
        }
        Insert: {
          user_id: string
          message_id: string
          created_at?: string
        }
        Update: {
          user_id?: string
          message_id?: string
          created_at?: string
        }
      }
      folders: {
        Row: {
          id: string
          created_at: string
          owner_id: string
          name: string
        }
        Insert: {
          id?: string
          created_at?: string
          owner_id: string
          name: string
        }
        Update: {
          id?: string
          created_at?: string
          owner_id?: string
          name?: string
        }
      }
      folder_items: {
        Row: {
          folder_id: string
          message_id: string
          added_at: string
        }
        Insert: {
          folder_id: string
          message_id: string
          added_at?: string
        }
        Update: {
          folder_id?: string
          message_id?: string
          added_at?: string
        }
      }
    }
  }
}
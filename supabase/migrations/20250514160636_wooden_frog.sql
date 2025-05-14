/*
  # Update conversation policy

  1. Changes
    - Drop existing conversation policy for viewing conversations
    - Create new policy using conversation_participants table for access control
  
  2. Security
    - Ensures users can only view conversations they are participants in
    - Uses the conversation_participants table for more granular access control
*/

-- Drop the existing policy
DROP POLICY IF EXISTS "Users can view conversations they participate in" ON conversations;

-- Create the new policy using conversation_participants table
CREATE POLICY "Users can view conversations they participate in"
ON conversations
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM conversation_participants
    WHERE conversation_participants.conversation_id = conversations.id
    AND conversation_participants.user_id = auth.uid()
  )
);
/*
  # Update conversation policy

  1. Changes
    - Replace existing conversation policy with a new one that uses conversation_participants table
    - Ensures users can only view conversations they are participants in
    - More secure and efficient policy implementation

  2. Security
    - Drops existing policy
    - Creates new policy using conversation_participants table
    - Maintains row level security
*/

-- Drop the existing policy
DROP POLICY IF EXISTS "Users can view conversations they participate in" ON conversations;

-- Create new policy using conversation_participants table
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
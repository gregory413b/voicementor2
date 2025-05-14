/*
  # Create Initial Training Director (Final Approach)

  1. Create auth user for Dr. Greg Bottaro with explicit ID
  2. Create corresponding profile record
*/

DO $$ 
DECLARE
  new_user_id UUID := gen_random_uuid();
BEGIN
  -- Create the auth user with explicit ID
  INSERT INTO auth.users (
    id,
    instance_id,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    email_change,
    email_change_token_new,
    recovery_token
  ) VALUES (
    new_user_id,
    '00000000-0000-0000-0000-000000000000',
    'drgreg@catholicpsych.com',
    crypt('password', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Greg Bottaro"}',
    now(),
    now(),
    '',
    '',
    '',
    ''
  );

  -- Create the profile
  INSERT INTO profiles (
    id,
    full_name,
    role,
    created_at
  ) VALUES (
    new_user_id,
    'Greg Bottaro',
    'training_director',
    now()
  );
END $$;
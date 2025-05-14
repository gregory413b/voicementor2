/*
  # Create Initial Admin User
  
  1. Changes
    - Creates initial training director user in auth.users
    - Creates corresponding profile in profiles table
  
  2. Security
    - Password is hashed using bcrypt
    - Email is set as confirmed
*/

DO $$
DECLARE
  user_id uuid;
BEGIN
  -- Create the auth user
  INSERT INTO auth.users (
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
  )
  ON CONFLICT (email) DO NOTHING
  RETURNING id INTO user_id;

  -- Create the profile
  IF user_id IS NOT NULL THEN
    INSERT INTO profiles (
      id,
      full_name,
      role,
      created_at
    ) VALUES (
      user_id,
      'Greg Bottaro',
      'training_director',
      now()
    )
    ON CONFLICT (id) DO NOTHING;
  END IF;
END
$$;
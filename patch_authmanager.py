import re

with open("ChatAja/Core/API/AuthManager.swift", "r") as f:
    content = f.read()

# Remove signIn (email, password)
content = re.sub(r'    /// Login email \+ password\.\n    func signIn\(email: String, password: String\) async \{.+?    \}\n\n', '', content, flags=re.DOTALL)

# Remove signUp (email, password, displayName)
content = re.sub(r'    /// Daftar akun baru\.\n    func signUp\(email: String, password: String, displayName: String\) async \{.+?    \}\n\n', '', content, flags=re.DOTALL)

with open("ChatAja/Core/API/AuthManager.swift", "w") as f:
    f.write(content)


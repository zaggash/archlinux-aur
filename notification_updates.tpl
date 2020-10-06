{{#success build.status}}
  ✅ Arch Repo build #{{build.number}} of `{{repo.name}}` succeeded.
  ```
  No Updates
  ```
  🌐 {{ build.link }}

{{else}}
  ❌ Arch Repo build #{{build.number}} of `{{repo.name}}` failed.  
  ```
  No Updates
  ```
  🌐 {{ build.link }}

{{/success}}

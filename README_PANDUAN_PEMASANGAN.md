# SMART ASSESSMENT CBT Tahap 2
**SMP Negeri 1 Teluk Pakedai**

Paket awal aplikasi web CBT dengan Supabase Auth + PostgreSQL, hosting Vercel, pembuatan ujian, token, halaman siswa, simpan jawaban, dan penilaian pilihan ganda otomatis.

## Isi paket
- `index.html` — antarmuka guru dan siswa.
- `config.js` — tempat mengisi URL proyek dan anon/public key Supabase.
- `schema.sql` — tabel, kebijakan RLS, serta fungsi RPC.
- `vercel.json` — konfigurasi hosting statis.
- `manifest.webmanifest`, `sw.js` — metadata PWA dan cache aset dasar.

## Langkah pemasangan
1. Buat proyek di https://supabase.com dan simpan Project URL serta anon/public key.
2. Buka **SQL Editor** di Supabase, tempel seluruh isi `schema.sql`, lalu jalankan.
3. Daftarkan akun administrator melalui aplikasi setelah konfigurasi Supabase selesai.
4. Di Supabase > Authentication > Users, salin UUID akun administrator.
5. Di SQL Editor jalankan:
   `update public.profiles set role='admin', full_name='Administrator Sekolah' where id='UUID-AKUN-ADMIN';`
6. Isi `config.js` dengan Project URL dan anon/public key. **Jangan pernah memakai service_role key di browser.**
7. Uji login administrator, buat akun guru dan siswa. Akun baru otomatis menjadi `student`; administrator mengubah peran guru dan menetapkan kelas melalui SQL:
   `update public.profiles set role='teacher', full_name='Nama Guru' where id='UUID-GURU';`
   `update public.profiles set class_name='VIII A' where id='UUID-SISWA';`
8. Unggah folder ini ke repository GitHub, hubungkan repository ke https://vercel.com, lalu deploy. Framework: Other; Build Command dan Output Directory dapat dikosongkan atau output `.`.
9. Setelah deploy, buka URL Vercel, uji dengan akun percobaan guru dan siswa terlebih dahulu.

## Alur penggunaan
- Guru login, buat ujian, tambahkan soal, lalu terbitkan.
- Aplikasi membuat token acak dan menyimpan ujian serta soal ke Supabase.
- Guru menyalin tautan ujian dari menu daftar ujian. Bagikan tautan dan token kepada siswa melalui kanal sekolah.
- Siswa login menggunakan akun masing-masing, masukkan token, lalu mengerjakan.
- Jawaban disimpan melalui RPC saat online. Jika jaringan putus, jawaban disimpan sementara pada browser dan dicoba sinkron saat jaringan kembali.
- Pilihan ganda dinilai otomatis ketika siswa mengirim ujian. Esai masih perlu pemeriksaan guru; fitur editor nilai esai belum disediakan pada paket dasar ini.

## Batasan yang perlu diketahui
- Ini adalah **starter Tahap 2 yang harus dipasang dan diuji**, bukan layanan yang sudah aktif online. Belum ada URL sekolah yang diterbitkan.
- Pendaftaran mandiri membuat profil `student`. Admin perlu mengatur role dan kelas. Untuk produksi sekolah, sebaiknya pendaftaran siswa dibatasi/diundang oleh operator.
- Cache PWA hanya untuk aset aplikasi. Pengambilan paket soal offline dan pengiriman jawaban setelah offline masih memerlukan pengembangan lanjutan. Saat koneksi terputus, jawaban terakhir disimpan di localStorage browser; siswa jangan menghapus data browser sebelum sinkronisasi berhasil.
- Batas waktu ujian pada versi ini divalidasi ketika mulai ujian, belum ada penghentian otomatis berbasis timer pada layar siswa.
- Fitur impor CSV/DOCX/XLSX dari Tahap 1 belum dihubungkan ke database pada starter ini. Tambahkan soal lewat formulir; integrasi impor merupakan pekerjaan lanjutan.
- Penilaian esai, analisis butir soal, cetak berita acara, pengacakan per siswa, anti-kecurangan, dan dashboard statistik lanjutan belum termasuk.
- Sebelum digunakan pada ujian penting, lakukan uji coba dengan akun dummy dan jumlah perangkat yang mewakili peserta. Pastikan kebijakan privasi, pencadangan, dan persetujuan sekolah telah dipenuhi.

## Keamanan
- RLS aktif pada tabel utama; siswa tidak mendapat akses langsung ke token ujian dan memakai fungsi `start_exam` untuk validasi token.
- Hanya gunakan anon/public key pada browser. Service role key bersifat rahasia dan tidak boleh dimasukkan ke `config.js`, HTML, GitHub, atau Vercel static environment.
- Lindungi akun administrator dengan kata sandi kuat dan verifikasi email.

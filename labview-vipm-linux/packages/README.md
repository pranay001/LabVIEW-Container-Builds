# packages/

Drop your `.vip` package files here (Linux builds accept the same `.vip`
JKI VIPM package files as Windows). Everything with a `.vip` extension found
directly in this folder is installed into the image during `docker build`,
in filename-sorted order.

Not used for anything else — subfolders and non-`.vip` files are ignored.

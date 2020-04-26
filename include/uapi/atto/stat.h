#pragma once

#define S_IFMT  00170000
#define S_IFSOCK 0140000
#define S_IFLNK  0120000
#define S_IFREG  0100000
#define S_IFBLK  0060000
#define S_IFDIR  0040000
#define S_IFCHR  0020000
#define S_IFIFO  0010000
#define S_ISUID  0004000
#define S_ISGID  0002000
#define S_ISVTX  0001000

#define S_ISLNK(m)      (((m) & S_IFMT) == S_IFLNK)
#define S_ISREG(m)      (((m) & S_IFMT) == S_IFREG)
#define S_ISDIR(m)      (((m) & S_IFMT) == S_IFDIR)
#define S_ISCHR(m)      (((m) & S_IFMT) == S_IFCHR)
#define S_ISBLK(m)      (((m) & S_IFMT) == S_IFBLK)
#define S_ISFIFO(m)     (((m) & S_IFMT) == S_IFIFO)
#define S_ISSOCK(m)     (((m) & S_IFMT) == S_IFSOCK)

struct stat {
        unsigned long   st_dev;         /* Device.  */
        unsigned long   st_ino;         /* File serial number.  */
        unsigned int    st_mode;        /* File mode.  */
        unsigned int    st_nlink;       /* Link count.  */
        unsigned int    st_uid;         /* User ID of the file's owner.  */
        unsigned int    st_gid;         /* Group ID of the file's group. */
        unsigned long   st_rdev;        /* Device number, if device.  */
        unsigned long   __pad1;
        long            st_size;        /* Size of file, in bytes.  */
        int             st_blksize;     /* Optimal block size for I/O.  */
        int             __pad2;
        long            st_blocks;      /* Number 512-byte blocks allocated. */
        long            st_atime;       /* Time of last access.  */
        unsigned long   st_atime_nsec;
        long            st_mtime;       /* Time of last modification.  */
        unsigned long   st_mtime_nsec;
        long            st_ctime;       /* Time of last status change.  */
        unsigned long   st_ctime_nsec;
        unsigned int    __unused4;
        unsigned int    __unused5;
};

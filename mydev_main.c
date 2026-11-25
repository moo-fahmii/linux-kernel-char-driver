#include <linux/module.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/uaccess.h>

/* asm callbacks */

extern int mydev_open(struct inode *, struct file *);
extern int mydev_release(struct inode *, struct file *);
extern ssize_t mydev_read(struct file *, char __user *, size_t, loff_t *);
extern ssize_t mydev_write(struct file *, const char __user *, size_t, loff_t *);

extern int mydev_init_asm(void);
extern void mydev_exit_asm(void);

/* Prototypes for helpers (silences -Wmissing-prototypes) */
dev_t                        *mydev_get_devno_addr(void);
struct cdev                  *mydev_get_cdev_addr(void);
const struct file_operations *mydev_get_fops(void);
struct class                **mydev_get_class_addr(void);
void                          mydev_set_cdev_owner(struct cdev *cdev);
unsigned long                 mydev_copy_to_user(void __user *to, const void *from, unsigned long n);
unsigned long                 mydev_copy_from_user(void *to, const void __user *from, unsigned long n);

/* storage because cdev has __randomize_layout */
static dev_t mydev_devno;
static struct cdev mydev_cdev;
static struct class *mydev_class;

static const struct file_operations mydev_fops = {
    .owner = THIS_MODULE,
    .open = mydev_open,
    .read = mydev_read,
    .write = mydev_write,
    .release = mydev_release,
};

/* asm reads addr of c struct through these */
dev_t *mydev_get_devno_addr(void) {
    return &mydev_devno;
}
struct cdev *mydev_get_cdev_addr(void) {
    return &mydev_cdev;
}
const struct file_operations *mydev_get_fops(void) {
    return &mydev_fops;
}
struct class **mydev_get_class_addr(void) {
    return &mydev_class;
}

/* to fix randomized offset issue that asm cant do */
void mydev_set_cdev_owner(struct cdev *cdev) {
    cdev->owner = THIS_MODULE;
}

static int __init mydev_module_init(void) {
    return mydev_init_asm();
}
static void __exit mydev_module_exit(void) {
    return mydev_exit_asm();
}
module_init(mydev_module_init);
module_exit(mydev_module_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Mohamed");
MODULE_DESCRIPTION("Echo character device driver logic in assembly");
MODULE_VERSION("0.1");
/* Helpers for asm: copy_to_user/copy_from_user are inline functions on
 * modern kernels, not exported symbols. The compiler inlines them
 * correctly here; the asm calls these wrappers.
 */
unsigned long mydev_copy_to_user(void __user *to, const void *from, unsigned long n)
{
    return copy_to_user(to, from, n);
}

unsigned long mydev_copy_from_user(void *to, const void __user *from, unsigned long n)
{
    return copy_from_user(to, from, n);
}

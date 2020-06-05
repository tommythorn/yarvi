#ifndef _JTAGATLANTIC_H
#define _JTAGATLANTIC_H

/* For the library user, the JTAGATLANTIC is an opaque object. */
struct JTAGATLANTIC;

/* jtagatlantic_open: Open a JTAG Atlantic UART.
 * Parameters:
 *   cable:    Identifies the USB Blaster connected to the device (e.g. "USB-Blaster [3-2]").
 *             If NULL, the library chooses at will.
 *   device:   The number of the device inside the JTAG chain, starting from 1 for the first device.
 *             If -1, the library chooses at will.
 *   instance: The instance number of the JTAG Atlantic inside the device.
 *             If -1, the library chooses at will.
 * Returns:
 *   Pointer to JTAGATLANTIC instance.
 */
JTAGATLANTIC *jtagatlantic_open(char const *cable, int device, int instance, char const *progname);

/* jtagatlantic_get_info: Get information about the UART to which we have actually connected.
 * Parameters:
 *   atlantic: The JTAGATLANTIC.
 *   cable:    Pointer to a variable which will receive a pointer to the cable name.
 *             Memory is managed by the library, do not free the received pointer.
 *   device:   Pointer to an integer which will receive the device number.
 *   instance: Pointer to an integer which will receive the instance number.
 *   progname: Name of your program (used to inform a lock on the UART).
 */
void jtagatlantic_get_info(JTAGATLANTIC *atlantic, char const **cable, int *device, int *instance);

/* jtagatlantic_cable_warning: Check if cable is good for JTAG UART communication.
 * Parameters:
 *   atlantic: The JTAGATLANTIC.
 * Returns:
 *   0 if the cable is adequate for JTAG UART communication.
 *   2 otherwise (e.g. ByteBlaster, MasterBlaster or old USB-Blaster).
 */
int jtagatlantic_cable_warning(JTAGATLANTIC *atlantic);

/* jtagatlantic_get_error: Get the last error ocurred.
 * Parameters:
 *   progname: Pointer to a variable which will receive a pointer to the name of the program which
 *             is currently locking the UART (if error is -6).
 * Returns:
 *   The error code:
 *   -1 Unable to connect to local JTAG server.
 *   -2 More than one cable available, provide more specific cable name.
 *   -3 Cable not available
 *   -4 Selected cable is not plugged.
 *   -5 JTAG not connected to board, or board powered down.
 *   -6 Another program (progname) is already using the UART.
 *   -7 More than one UART available, specify device/instance.
 *   -8 No UART matching the specified device/instance.
 *   -9 Selected UART is not compatible with this version of the library.
 */
int jtagatlantic_get_error(char const **progname); 

/* jtagatlantic_read: Read data from the UART.
 * Parameters:
 *   atlantic: The JTAGATLANTIC.
 *   data:     Pointer to data.
 *   len:      Maximum amount of data to read.
 * Returns:
 *   -1 if connection was broken.
 *   otherwise the number of chars received.
 */
int jtagatlantic_read(JTAGATLANTIC *atlantic, char *data, unsigned int len);

/* jtagatlantic_write: Write data to the UART.
 * Parameters:
 *   atlantic: The JTAGATLANTIC.
 *   data:     Pointer to data.
 *   len:      Maximum amount of data to write.
 * Returns:
 *   -1 if connection was broken.
 *   otherwise the number of chars copied to send buffer.
 */
int jtagatlantic_write(JTAGATLANTIC *atlantic, char const *data, unsigned int len);

/* jtagatlantic_close: Close the UART. */
void jtagatlantic_close(JTAGATLANTIC *atlantic);

/* jtagatlantic_flush: Wait for data to be flushed from the send buffer. */
int jtagatlantic_flush(JTAGATLANTIC *atlantic);

/* jtagatlantic_is_setup_done: Return non-zero if UART setup is done. */
int jtagatlantic_is_setup_done(JTAGATLANTIC*);

/* jtagatlantic_wait_open: Wait for UART setup to be done. */
int jtagatlantic_wait_open(JTAGATLANTIC *atlantic);

/* jtagatlantic_bytes_available: Return number of bytes available for reading */
int jtagatlantic_bytes_available(JTAGATLANTIC *atlantic);

#endif

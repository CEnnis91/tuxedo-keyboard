obj-m := ./src/tuxedo_keyboard.o

tuxedo_tuxedo-objs := ./src/tuxedo_keyboard.o

CONTROLLER := tuxedo_controller.sh
PWD := $(shell pwd)
KDIR := /lib/modules/$(shell uname -r)/build

all:
	make -C $(KDIR) M=$(PWD) modules

clean:
	make -C $(KDIR) M=$(PWD) clean

ctrladd:
	cp -f ./src/$(CONTROLLER) /usr/local/bin/$(CONTROLLER)
	chmod 755 /usr/local/bin/$(CONTROLLER)

	cp -R ./etc/systemd/system/*.service /etc/systemd/system
	systemctl daemon-reload
	systemctl enable tuxedo-preserve.service
	systemctl enable tuxedo-restore.service
	systemctl enable tuxedo-monitor.service
	systemctl start tuxedo-monitor.service

ctrlremove:
	rm -rf /usr/local/bin/$(CONTROLLER)
	rm -rf /etc/systemd/system/tuxedo-*.service
	systemctl daemon-reload

install:
	make -C $(KDIR) M=$(PWD) modules_install

dkmsadd:
	cp -R . /usr/src/tuxedo_keyboard-2.0.0
	dkms add -m tuxedo_keyboard -v 2.0.0

dkmsremove:
	dkms remove -m tuxedo_keyboard -v 2.0.0 --all
	rm -rf /usr/src/tuxedo_keyboard-2.0.0

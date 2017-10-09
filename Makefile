# Install prefix
PREFIX ?= /usr

MANDIR ?= $(PREFIX)/share/man/

SHA1SUM ?= /usr/bin/sha1sum
LSB_RELEASE ?= /usr/bin/lsb_release
WHOAMI ?= /usr/bin/whoami

# Distro name: Ubuntu, Debian, Fedora, if not present you get
# "custom-distro", if your distribution does not have the LSB stuff,
# then set this variable when calling make if you don't want "custom-distro"
LSB_ID ?= $(shell if [ -f $(LSB_RELEASE) ]; then \
			$(LSB_RELEASE) -i -s; \
		else \
			echo custom-distro; \
		fi)

DISTRO_PRIVKEY ?= ~/.wireless-regdb-$(LSB_ID).key.priv.pem
DISTRO_PUBKEY ?= ~/.wireless-regdb-$(LSB_ID).key.priv.pem

REGDB_AUTHOR ?= $(shell if [ -f $(DISTRO_PRIVKEY) ]; then \
			echo $(LSB_ID) ; \
		elif [ -f $(WHOAMI) ]; then \
			$(WHOAMI); \
		else \
			echo custom-user; \
		fi)

REGDB_PRIVKEY ?= ~/.wireless-regdb-$(REGDB_AUTHOR).key.priv.pem
REGDB_PUBCERT ?= $(REGDB_AUTHOR).x509.pem

REGDB_CHANGED = $(shell $(SHA1SUM) -c --status sha1sum.txt >/dev/null 2>&1; \
        if [ $$? -ne 0 ]; then \
                echo maintainer-clean $(REGDB_PUBCERT); \
        fi)

.PHONY: all clean mrproper install maintainer-clean install-distro-key

all: $(REGDB_CHANGED) regulatory.db.p7s sha1sum.txt

clean:
	@rm -f *.pyc *.gz

maintainer-clean: clean
	@rm -f regulatory.db regulatory.db.p7s

mrproper: clean maintainer-clean
	@echo Removed public key, regulatory.db* and compressed man pages
	@rm -f $(REGDB_PUBCERT) .custom

regulatory.db: db.txt db2fw.py
	@echo "Generating $@"
	./db2fw.py regulatory.db db.txt

regulatory.db.p7s: regulatory.db $(REGDB_PRIVKEY) $(REGDB_PUBCERT)
	@echo "Signing regulatory.db (by $(REGDB_AUTHOR))..."
	@openssl smime -sign \
		-signer $(REGDB_PUBCERT) \
		-inkey $(REGDB_PRIVKEY) \
		-in $< -nosmimecap -binary \
		-outform DER -out $@

sha1sum.txt: db.txt
	sha1sum $< > $@

$(REGDB_PUBCERT): $(REGDB_PRIVKEY)
	@echo "Generating certificate for $(REGDB_AUTHOR)..."
	@openssl req -config regulatory.openssl.conf \
		-key $(REGDB_PRIVKEY) -days 36500 -utf8 -nodes -batch \
		-x509 -outform PEM -out $(REGDB_PUBCERT)
	@echo $(REGDB_PUBKEY) > .custom


$(REGDB_PRIVKEY):
	@echo "Generating private key for $(REGDB_AUTHOR)..."
	openssl genrsa -out $(REGDB_PRIVKEY) 2048

ifneq ($(shell test -e $(DISTRO_PRIVKEY) && echo yes),yes)
$(DISTRO_PRIVKEY):
	@echo "Generating private key for $(LSB_ID) packager..."
	openssl genrsa -out $(DISTRO_PRIVKEY) 2048
endif

install-distro-key: maintainer-clean $(DISTRO_PRIVKEY)

%.gz: %
	gzip < $< > $@

# Users should just do:
#	sudo make install
#
# Developers should do:
#	make maintainer-clean
#	make
#	sudo make install
#
# Distributions packagers should do only once:
#	make install-distro-key
# This will create a private key for you and install it into
# ~/.wireless-regdb-$(LSB_ID).key.priv.pem
# To make new releaes just do:
#	make maintainer-clean
#	make
#	sudo make install
install: regulatory.db.5.gz
	install -m 644 -t $(DESTDIR)/$(CRDA_PATH)/ regulatory.db
	install -m 755 -d $(DESTDIR)/$(MANDIR)/man5/
	install -m 644 -t $(DESTDIR)/$(MANDIR)/man5/ regulatory.db.5.gz

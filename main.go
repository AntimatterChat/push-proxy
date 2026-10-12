// Copyright (c) 2015 Mattermost, Inc. All Rights Reserved.
// See License.txt for license information.

package main

import (
	"flag"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/AntimatterChat/push-proxy/internal/version"
	"github.com/AntimatterChat/push-proxy/server"
)

const (
	defaultConfigFile = "antimatter-push-proxy.json"
	// legacyConfigFile is the name the config file had before the rename to
	// Antimatter. It is still read when no file with the new name exists, so
	// existing installations keep working.
	legacyConfigFile = "mattermost-push-proxy.json"
)

var (
	flagConfigFile string
	falgVersion    bool
)

func main() {
	flag.StringVar(&flagConfigFile, "config", defaultConfigFile, "path to the configuration file")
	flag.BoolVar(&falgVersion, "version", false, "print the version and exit")
	flag.Parse()

	if falgVersion {
		if err := version.GetVersion(); err != nil {
			log.Fatal(err)
		}

		os.Exit(0)
	}

	configFlagSet := false
	flag.Visit(func(f *flag.Flag) {
		if f.Name == "config" {
			configFlagSet = true
		}
	})

	fileName := server.FindConfigFile(flagConfigFile)
	if !configFlagSet && !fileExists(fileName) {
		if legacy := server.FindConfigFile(legacyConfigFile); fileExists(legacy) {
			fileName = legacy
		}
	}
	cfg, err := server.LoadConfig(fileName)
	if err != nil {
		// We just do a hard exit, because the app won't be able to start without a config.
		log.Fatal(err)
	}

	logger, err := server.NewLogger(cfg)
	defer func() {
		if logger != nil {
			_ = logger.Shutdown()
		}
	}()
	if err != nil {
		log.Fatal(err)
	}

	logger.Info("Loading " + fileName)

	srv := server.New(cfg, logger)
	srv.Start()

	// wait for kill signal before attempting to gracefully shutdown
	// the running service
	stopChan := make(chan os.Signal, 1)
	signal.Notify(stopChan, os.Interrupt, syscall.SIGINT, syscall.SIGTERM)
	<-stopChan

	srv.Stop()
}

func fileExists(name string) bool {
	_, err := os.Stat(name)
	return err == nil
}

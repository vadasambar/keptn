package main

import (
	keptnv2 "github.com/keptn/go-utils/pkg/lib/v0_2_0"
	"github.com/keptn/keptn/go-sdk/pkg/sdk"
	"log"
)

const (
	greetingTriggeredEvent = "sh.keptn.event.get-action.triggered"
	serviceName            = "simple-keptn-integration"
)

func main() {
	log.Fatal(
		sdk.NewKeptn(
			serviceName,
			sdk.WithHandler(greetingTriggeredEvent, &MyHandler{}, &MyEvent{})).Start())
}

type MyEvent struct {
	keptnv2.EventData
	Message string
}

type MyHandler struct {

}

func (m MyHandler) Execute(keptnHandle sdk.IKeptn, data interface{}) (interface{}, *sdk.Error) {
	panic("implement me")
}


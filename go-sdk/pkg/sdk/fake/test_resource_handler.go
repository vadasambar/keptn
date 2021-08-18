package fake

import (
	"fmt"
	"github.com/keptn/go-utils/pkg/api/models"
	"io/ioutil"
)

type TestResourceHandler struct {
}

func (t TestResourceHandler) GetServiceResource(project string, stage string, service string, resourceURI string) (*models.Resource, error) {
	return newResourceFromFile(fmt.Sprintf("test/keptn/resources/%s/%s/%s/%s", project, stage, service, resourceURI)), nil
}

func (t TestResourceHandler) GetStageResource(project string, stage string, resourceURI string) (*models.Resource, error) {
	return newResourceFromFile(fmt.Sprintf("test/keptn/resources/%s/%s/%s", project, stage, resourceURI)), nil
}

func (t TestResourceHandler) GetProjectResource(project string, resourceURI string) (*models.Resource, error) {
	return newResourceFromFile(fmt.Sprintf("test/keptn/resources/%s/%s", project, resourceURI)), nil
}

func newResourceFromFile(filename string) *models.Resource {
	content, err := ioutil.ReadFile(filename)
	if err != nil {
		return nil
	}

	return &models.Resource{
		Metadata:        nil,
		ResourceContent: string(content),
		ResourceURI:     nil,
	}
}
// SPDX-License-Identifier: Apache-2.0
package hwip

import "fmt"

// SubmitterFactory creates a Submitter for a given shm name.
// Register one per hwip type (e.g. "accel", "codec").
type SubmitterFactory func(shmName string) Submitter

var factories = map[string]SubmitterFactory{}

// Register associates hwipType with factory.  Call from an init() function in
// the hwip plugin package (e.g. hwip/accel/server) or from main().
func Register(hwipType string, factory SubmitterFactory) {
	factories[hwipType] = factory
}

// NewSubmitter creates a Submitter for the registered hwipType.
// Returns an error if hwipType has not been registered.
func NewSubmitter(hwipType, shmName string) (Submitter, error) {
	fn, ok := factories[hwipType]
	if !ok {
		return nil, fmt.Errorf("hwip: unknown type %q (registered: %v)", hwipType, registeredTypes())
	}
	return fn(shmName), nil
}

// NewServiceFromRegistry creates a Service using the Submitter registered for hwipType.
func NewServiceFromRegistry(hwipType, shmName string) (*Service, error) {
	sub, err := NewSubmitter(hwipType, shmName)
	if err != nil {
		return nil, err
	}
	return newServiceWithSubmitter(sub), nil
}

func registeredTypes() []string {
	types := make([]string, 0, len(factories))
	for t := range factories {
		types = append(types, t)
	}
	return types
}

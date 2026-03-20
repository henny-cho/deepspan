// SPDX-License-Identifier: Apache-2.0
package hwip

import (
	"errors"
	"fmt"
)

// ErrNoPlugin is returned when no plugin has been registered for the requested
// hwip type.  Callers (e.g. platform server started without a plugin binary)
// receive this error and should exit with a clear diagnostic.
var ErrNoPlugin = errors.New("no plugin registered for hwip type")

// SubmitterFactory creates a Submitter for a given shm name.
// Register one per hwip type (e.g. "accel", "codec").
type SubmitterFactory func(shmName string) Submitter

var factories = map[string]SubmitterFactory{}

// Register associates hwipType with factory.  Call from an init() function in
// the hwip plugin package (e.g. deepspan-hwip/accel/server) or from main().
func Register(hwipType string, factory SubmitterFactory) {
	factories[hwipType] = factory
}

// NewSubmitter creates a Submitter for the registered hwipType.
// Returns ErrNoPlugin if hwipType has not been registered.
func NewSubmitter(hwipType, shmName string) (Submitter, error) {
	fn, ok := factories[hwipType]
	if !ok {
		return nil, fmt.Errorf("%w: %q (registered: %v)", ErrNoPlugin, hwipType, registeredTypes())
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

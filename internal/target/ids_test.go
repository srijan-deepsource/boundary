package target_test

import (
	"strings"
	"testing"

	"github.com/hashicorp/boundary/internal/target"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func Test_Ids(t *testing.T) {
	t.Parallel()
	t.Run("tcp", func(t *testing.T) {
		id, err := target.NewTcpTargetId()
		require.NoError(t, err)
		assert.True(t, strings.HasPrefix(id, target.TcpTargetPrefix+"_"))
	})
}

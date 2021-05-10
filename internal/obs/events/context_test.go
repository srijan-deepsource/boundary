package event_test

import (
	"context"
	"encoding/json"
	"io/ioutil"
	"os"
	"strings"
	"testing"

	event "github.com/hashicorp/boundary/internal/obs/events"
	"github.com/hashicorp/go-hclog"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func Test_WriteInfo(t *testing.T) {

	logger := hclog.New(&hclog.LoggerOptions{
		Name: "test",
	})

	tmpFile, err := ioutil.TempFile("./", "test_writeinfo-info")
	require.NoError(t, err)
	tmpFile.Close()
	defer os.Remove(tmpFile.Name()) // just to be sure it's gone after all the tests are done.

	tmpErrFile, err := ioutil.TempFile("./", "test_writeinfo-err")
	require.NoError(t, err)
	tmpErrFile.Close()
	defer os.Remove(tmpErrFile.Name()) // just to be sure it's gone after all the tests are done.

	c := event.EventerConfig{
		InfoEnabled:  true,
		InfoDelivery: event.Enforced,
		Sinks: []event.SinkConfig{
			{
				Name:       "info-file-sink",
				EventTypes: []event.Type{event.EveryType},
				Format:     event.JSONSinkFormat,
				Path:       "./",
				FileName:   tmpFile.Name(),
			},
			{
				Name:       "stdout",
				EventTypes: []event.Type{event.EveryType},
				Format:     event.JSONSinkFormat,
				SinkType:   event.StdoutSink,
			},
			{
				Name:       "err-file-sink",
				EventTypes: []event.Type{event.ErrorType},
				Format:     event.JSONSinkFormat,
				Path:       "./",
				FileName:   tmpErrFile.Name(),
			},
		},
	}
	e, err := event.NewEventer(logger, c)
	require.NoError(t, err)

	info := &event.RequestInfo{Id: "867-5309"}

	testHdr := map[string]interface{}{
		"name": "bar",
		"list": []string{"1", "2"},
	}

	ctx, err := event.NewEventerContext(context.Background(), e)
	require.NoError(t, err)
	ctx, err = event.NewRequestInfoContext(ctx, info)
	require.NoError(t, err)

	tests := []struct {
		name             string
		header           map[string]interface{}
		details          map[string]interface{}
		ctx              context.Context
		errSinkFileName  string
		infoSinkFileName string
		wantFileSink     string
	}{
		{
			name:             "simple",
			ctx:              ctx,
			header:           testHdr,
			errSinkFileName:  tmpErrFile.Name(),
			infoSinkFileName: tmpFile.Name(),
			wantFileSink:     "first",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert, require := assert.New(t), require.New(t)
			err := event.WriteInfo(tt.ctx, event.Op(tt.name), event.WithHeader(tt.header))
			require.NoError(err)

			if tt.infoSinkFileName != "" {
				defer os.Remove(tt.infoSinkFileName)
				b, err := ioutil.ReadFile(tt.infoSinkFileName)
				require.NoError(err)
				gotInfo := &eventJson{}
				err = json.Unmarshal(b, gotInfo)
				require.NoError(err)
				wantJson := testInfoJsonFromCtx(t, tt.ctx, event.Op(tt.name), gotInfo.Payload["id"].(string), gotInfo.CreatedAt, tt.header, tt.details)
				assert.Equal(string(wantJson), strings.TrimSuffix(string(b), "\n"))
			}

			if tt.errSinkFileName != "" {
				defer os.Remove(tt.errSinkFileName)
				b, err := ioutil.ReadFile(tt.errSinkFileName)
				require.NoError(err)
				assert.Equal(0, len(b))
			}
		})
	}

}

func testInfoJsonFromCtx(t *testing.T, ctx context.Context, caller event.Op, Id, createdAt string, hdr, details map[string]interface{}) []byte {
	t.Helper()
	require := require.New(t)

	reqInfo, ok := ctx.Value(event.RequestInfoKey).(*event.RequestInfo)
	require.Truef(ok, "missing reqInfo in ctx")

	j := eventJson{
		CreatedAt: createdAt,
		EventType: string(event.InfoType),
		Payload: map[string]interface{}{
			"id":           Id,
			"op":           string(caller),
			"request_info": reqInfo,
		},
	}
	if hdr != nil {
		j.Payload["header"] = hdr
	}
	if details != nil {
		j.Payload["details"] = details
	}
	b, err := json.Marshal(j)
	require.NoError(err)
	return b
}

type eventJson struct {
	CreatedAt string                 `json:"created_at"`
	EventType string                 `json:"event_type"`
	Payload   map[string]interface{} `json:"payload"`
}

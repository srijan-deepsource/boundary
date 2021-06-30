// Code generated by "make handlers"; DO NOT EDIT.
package accounts

import (
	"context"

	"github.com/hashicorp/boundary/internal/auth"
	"github.com/hashicorp/boundary/internal/auth/oidc"
	"github.com/hashicorp/boundary/internal/errors"
	pbs "github.com/hashicorp/boundary/internal/gen/controller/api/services"
	"github.com/hashicorp/boundary/internal/intglobals"
	"github.com/hashicorp/boundary/internal/types/action"
	"github.com/hashicorp/boundary/internal/servers/controller/handlers"
)

type deleteRequest = *pbs.DeleteAccountRequest
type deleteResponse = *pbs.DeleteAccountResponse

// DeleteAccount implements the interface pbs.CredentialLibraryServiceServer.
func (s Service) DeleteAccount(ctx context.Context, req deleteRequest) (deleteResponse, error) {
	if err := validateDeleteRequest(req); err != nil {
		return nil, err
	}
	authResults := s.authResult(ctx, req.GetId(), action.Delete)
	if authResults.Error != nil {
		return nil, authResults.Error
	}
	_, err := s.deleteFromRepo(ctx, authResults.Scope.GetId(), req.GetId())
	if err != nil {
		return nil, err
	}
	return nil, nil
}

func (s Service) deleteFromRepo(ctx context.Context, scopeId, id string) (bool, error) {
	const op = "accounts.(Service).deleteFromRepo"
	var rows int
	var err error
	
	switch auth.SubtypeFromId(id) {
	
	case auth.OidcSubtype:
		repo, iErr := s.oidcRepoFn()
		if iErr != nil {
			return false, iErr
		}
		rows, err = repo.DeleteAccount(ctx, scopeId, id)
	
	case auth.PasswordSubtype:
		repo, iErr := s.pwRepoFn()
		if iErr != nil {
			return false, iErr
		}
		rows, err = repo.DeleteAccount(ctx, scopeId, id)
	
	default:
		// We don't know the type being deleted
		return false, nil
    }
	
	if err != nil {
		if errors.IsNotFoundError(err) {
			return false, nil
		}
		return false, errors.Wrap(err, op, errors.WithMsg("unable to delete resource"))
	}
	return rows > 0, nil
}

func validateDeleteRequest(req deleteRequest) error {
	return handlers.ValidateDeleteRequest(handlers.NoopValidatorFn, req, oidc.AccountPrefix,intglobals.OldPasswordAccountPrefix,intglobals.NewPasswordAccountPrefix,)
}
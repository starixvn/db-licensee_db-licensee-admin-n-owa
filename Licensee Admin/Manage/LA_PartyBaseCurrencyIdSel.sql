/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_PartyBaseCurrencyIdSel]
	@PartyId INT = 0
AS
/*
	Created: 20210318@Happy
	Task : Get base currency Id of payer
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20210318@Happy: Initialize SP

	Params:
		- 0: get all
		- <> 0: specific party
	Example:
		EXEC dbo.LA_PartyBaseCurrencyIdSelSel
*/
BEGIN
	SET NOCOUNT ON

	SELECT BaseCurrencyId AS CurrencyId
	FROM dbo.OAS_PartyBaseCurrency p WITH(NOLOCK)
	WHERE (@PartyId = 0 OR PartyID = @PartyId)
END
GO
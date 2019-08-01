/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].LA_LicenseeBillingCurrencySel(@UserID INT = 0,@FunctionID INT = 0)
AS
/*	Header:
	Task : Get licensee base currency
	DB: DBLIC.bodb_Licensee
   
	Revisions: 
		- 20190723@Bruce: Create Sp
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @allParty TABLE(
		PartyId		INT,
		PartyName	VARCHAR(50),
		BrandName	VARCHAR(50),
		ParentId	INT
	)
	INSERT INTO @allParty(PartyId,PartyName,BrandName,ParentId)
	EXEC dbo.LA_PartyListSel @UserID, @FunctionID

	DELETE @allParty WHERE ParentId = 0

	SELECT p.PartyId, p.PartyName,l.LicenseeName,d.BaseCurrencyId
	FROM @allParty p
	INNER JOIN OAS_Party p2 WITH(NOLOCK) ON p.PartyId=p2.PartyID
	INNER JOIN dbo.OAS_PartyDetail d WITH(NOLOCK) ON p.PartyId=d.PartyID
	INNER JOIN dbo.Licensees l WITH(NOLOCK) ON l.LicenseeID=p2.OldRefID
	WHERE d.IsDeposit = 1
END
GO
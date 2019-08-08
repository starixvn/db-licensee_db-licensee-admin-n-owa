/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

ALTEr PROCEDURE [dbo].LA_PartyBaseCurrencySel
AS
/*	Header:
	Task : Get licensee base currency
	DB: DBCUST.bodb_Licensee
   
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
	EXEC dbo.LA_PartyListSel

	DELETE @allParty WHERE ParentId = 0

	SELECT p.PartyId, p.PartyName,e.Code AS BaseCurrencyCode,d.BaseCurrencyId
	FROM @allParty p
	INNER JOIN dbo.OAS_Party p2 WITH(NOLOCK) ON p.PartyId=p2.PartyID
	INNER JOIN dbo.OAS_PartyDetail d WITH(NOLOCK) ON p.PartyId=d.PartyID
	INNER JOIN CustDb.dbo.Exchange e WITH(NOLOCK) ON d.BaseCurrencyId=e.exchangeid
	WHERE d.IsDeposit = 1
END
GO
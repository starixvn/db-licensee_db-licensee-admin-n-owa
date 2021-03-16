/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_PayerInfoSel]
	 @PayerId	INT	= 0,
	 @BillerId	INT = 0,
	 @InvoiceTypeId INT = 0
AS
/*
	 Created: 20150414@Florent
	 Task : get Payer Information by Id
	 DB: DBCUST.bodb_Licensee

	 Revisions:
		+ 20160808@Bravo: Hosting fees
		+ 20160905@Bruce: Default active address is 1
		+ 20161109@Bruce: Include non-official payers
			1: official payer
			5: non-official payer
		+ 20190318@Mason: Add Invoice Language in SELECT statement [#110419]
		+ 20190829@Bruce: Adding Licensee Code [#111586]
		+ 20210315@Happy: Change BaseCurrency Of Licensee [#151466]
		
	 Params:
	 Example:
		EXEC dbo.LA_PayerInfoSel 14
*/
BEGIN
SET NOCOUNT ON
	DECLARE @CurrentDate DATE = CONVERT(DATE, GETDATE())
	SELECT TOP 1 p.PartyID AS PayerID
		, p.PartyName AS PayerName
		, pd.StatusId
		, pd.IsDeposit
		, pd.BrandName
		, pd.CompanyName
		, pd.AttnName
		, pd.Description
		, pd.Address1
		, pd.Address2
		, ISNULL(i.ActiveAddress, 1) AS ActiveAddress
		, p.PartyType
		, ISNULL(p.SetupName, '') AS SetupName
		, ISNULL(pd.BaseCurrencyId, 0) BaseCurrencyId
		, pd.InvoiceLanguage
		, pd.LicenseeCode
	FROM dbo.OAS_Party p WITH (NOLOCK)
		LEFT JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID
		LEFT JOIN (
			SELECT i.FromPartyId, i.ToPartyId, i.InvTypeId, ActiveAddress
			FROM dbo.LA_InvoiceSetting i
			WHERE (@BillerId = 0 OR i.ToPartyId = @BillerId) AND (@InvoiceTypeId = 0 OR InvTypeId = @InvoiceTypeId)
			GROUP BY i.FromPartyId, i.ToPartyId, i.InvTypeId, i.ActiveAddress
		) i ON p.PartyID = i.FromPartyId
	WHERE (@PayerId = 0 OR p.PartyID = @PayerId)
		AND p.PartyType IN (1,5)
		
	SELECT p.PartyID
		, p.BaseCurrencyId
		, e.Code AS BaseCurrencyName
		, p.LicenseeCode
		, p.FromDate
		, p.ToDate
		, CASE WHEN p.ToDate < @CurrentDate THEN 0 ELSE 1 END AS IsActive
	FROM OAS_PartyBaseCurrency p WITH(NOLOCK)
	LEFT JOIN CustDB.dbo.Exchange e WITH (NOLOCK) ON p.BaseCurrencyId = e.exchangeid
	WHERE PartyID = @PayerId
	ORDER BY p.ToDate DESC
END
GO
/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceBillerInfoGet] 
	  @BillerId		INT
	, @PayerId		INT
	, @InvoiceType	INT
	, @Environment	VARCHAR(20)
AS
/*	Header:
	Created: 2015.08.06 - Bravo.Tran
	Task : Create Invoice 
	DB: DBCUST.bodb_Licensee

	Revisions: 
		- 20150806@Bravo: Invoice Biller Info - Get
		- 20151019@Victor: Support Chinese on Invoice's text fields
		- 20160728@Bruce: Software data fee & hosting fee have a same invoice no
		- 20170421@Bruce: Add environment filter
		- 20170824@Bruce: use same invoice no for debit note and debit note for return amf [#76410]
		- 20171128@Bruce: use created date time instead of invoice date [#86399]
		- 20171205@Bruce: exclude void invoice [#87723]
		- 20190326@Bruce: Include invoice language [#102830]
		- 20210705@Sophia: Revise, fix the MAX(InvoiceNumber) [Redmine: #158041]
		- 20240410@Danny: Return biller CompanyName & Address1  [Redmine: #194604]
		- 20240819@Danny:  get lastest invoice number and symbol by created datetime [#209325]
*/
/*	Example:
	USE bodb_licensee
	DECLARE @BillerId INT = 115
	DECLARE @PartyId INT = 17
	DECLARE @InvoiceType INT = 1
	EXEC LA_Inv_InvoiceBillerInfoGet @BillerId, @PartyId, @InvoiceType
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @InvoiceInfo AS TABLE(
		InvoiceSymbol		NVARCHAR(20),
		InvoiceNumber		INT,
		InvoiceTemplateId	SMALLINT,
		InvoiceTemplateName	VARCHAR(50),
		InvoiceTemplatePath	VARCHAR(255),
		IsSeparateProduct	BIT,
		InvoiceLanguage		VARCHAR(50),
		ActiveAddress		TINYINT,
		CompanyName			NVARCHAR(100), 
		BillerAddress1		NVARCHAR(255)
	)
	INSERT INTO @InvoiceInfo(InvoiceTemplateId,InvoiceTemplateName,InvoiceTemplatePath,ActiveAddress)
	(
		SELECT	ivs.InvTempId, itpl.InvTemplateName, itpl.TemplatePath, ivs.ActiveAddress
		FROM	dbo.LA_InvoiceSetting ivs WITH(NOLOCK) 
				INNER JOIN dbo.LA_InvoiceTemplate itpl WITH(NOLOCK) ON ivs.InvTempId = itpl.InvTemplateId
		WHERE	ivs.FromPartyId = @PayerId
				AND ivs.ToPartyId = @BillerId
				AND ivs.InvTypeId = @InvoiceType
		GROUP	BY ivs.InvTempId, itpl.InvTemplateName, itpl.TemplatePath, ivs.ActiveAddress
	)

	DECLARE @InvoiceTmp TABLE(
			BillerId		INT,
			InvoiceType		INT,
			InvoiceSymbol	NVARCHAR(20),
			InvoiceNumber	INT,
			CreatedDateTime  DATETIME)

	INSERT	INTO @InvoiceTmp
	SELECT	i.BillerId,
			i.InvoiceType,
			i.InvoiceSymbol,
			MAX(i.InvoiceNumber),
			i.CreatedDateTime
	FROM	LA_InvoiceHeader i WITH(NOLOCK)
	WHERE	i.BillerId = @BillerId AND (i.Environment IS NULL OR i.Environment = @Environment) AND ISNULL(StatusId,0) <> -1
	GROUP BY i.BillerId,i.InvoiceType,i.InvoiceSymbol , i.CreatedDateTime

	DECLARE @InvoiceSymbol NVARCHAR(20) = ''
	DECLARE @InvoiceNumber INT = 1
	DECLARE @SameInvoiceNoList TABLE (InvoiceType INT)

	-- 1: software fee, 6: hosting fee
	IF @InvoiceType IN (1,6,3,7) INSERT INTO @SameInvoiceNoList VALUES(1),(6),(3),(7)
	-- 5: debit note, 10: debit note for return AMF
	ELSE IF @InvoiceType IN (5,10) INSERT INTO @SameInvoiceNoList VALUES(5),(10)
	-- others
	ELSE INSERT INTO @SameInvoiceNoList VALUES(@InvoiceType)

	SELECT	TOP 1 @InvoiceSymbol = i.InvoiceSymbol
	FROM	@InvoiceTmp i
	WHERE	i.InvoiceType IN (SELECT * FROM @SameInvoiceNoList)  order by CreatedDateTime desc

	SELECT	@InvoiceNumber = ISNULL(MAX(i.InvoiceNumber), 0) + 1
	FROM	@InvoiceTmp i		
	WHERE	i.InvoiceSymbol = @InvoiceSymbol

	UPDATE	t
	SET		t.InvoiceSymbol = @InvoiceSymbol,
			t.InvoiceNumber = @InvoiceNumber,
			t.InvoiceLanguage = u.InvoiceLanguage,
			t.CompanyName		= u.CompanyName,
			t.BillerAddress1	= u.BillerAddress1
	FROM @InvoiceInfo t
	OUTER APPLY (
		SELECT TOP 1 d.InvoiceLanguage,
			   CASE WHEN t.ActiveAddress = 1 THEN d.CompanyName
					WHEN t.ActiveAddress = 2 THEN d.CompanyName2  END CompanyName, 
				CASE WHEN t.ActiveAddress = 1 THEN d.Address1
					WHEN t.ActiveAddress = 2 THEN d.Address2  END BillerAddress1
		FROM dbo.OAS_PartyDetail d WHERE d.PartyID=@PayerId
	) u
	
	UPDATE	@InvoiceInfo
	SET		IsSeparateProduct = (SELECT TOP 1 i.IsSeparateProduct
								FROM LA_InvoiceHeader i WITH(NOLOCK)
								WHERE i.BillerId = @BillerId
								ORDER BY i.InvoiceNumber DESC)
	
	SELECT TOP 1 ii.InvoiceSymbol
		, ii.InvoiceNumber
		, ii.InvoiceTemplateId
		, ii.InvoiceTemplateName
		, ii.InvoiceTemplatePath
		, ISNULL(ii.IsSeparateProduct,0) AS IsSeparateProduct
		, ISNULL(ii.InvoiceLanguage, 'en-US') AS InvoiceLanguage
		, ii.CompanyName  AS CompanyName
		, ii.BillerAddress1 AS BillerAddress1
	FROM @InvoiceInfo ii

END
GO

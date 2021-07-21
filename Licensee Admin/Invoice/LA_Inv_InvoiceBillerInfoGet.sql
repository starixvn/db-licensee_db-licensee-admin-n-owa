/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
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
		InvoiceLanguage		VARCHAR(50)
	)
	INSERT INTO @InvoiceInfo(InvoiceTemplateId,InvoiceTemplateName,InvoiceTemplatePath)
	(
		SELECT	ivs.InvTempId, itpl.InvTemplateName, itpl.TemplatePath
		FROM	dbo.LA_InvoiceSetting ivs WITH(NOLOCK) 
				INNER JOIN dbo.LA_InvoiceTemplate itpl WITH(NOLOCK) ON ivs.InvTempId = itpl.InvTemplateId
		WHERE	ivs.FromPartyId = @PayerId
				AND ivs.ToPartyId = @BillerId
		GROUP	BY ivs.InvTempId, itpl.InvTemplateName, itpl.TemplatePath
	)

	DECLARE @InvoiceTmp TABLE(
			BillerId		INT,
			InvoiceType		INT,
			InvoiceSymbol	NVARCHAR(20),
			InvoiceNumber	INT)
	INSERT	INTO @InvoiceTmp
	SELECT	i.BillerId,
			i.InvoiceType,
			i.InvoiceSymbol,
			MAX(i.InvoiceNumber)
	FROM	LA_InvoiceHeader i WITH(NOLOCK)
	WHERE	i.BillerId = @BillerId AND (i.Environment IS NULL OR i.Environment = @Environment) AND ISNULL(StatusId,0) <> -1
	GROUP BY i.BillerId,i.InvoiceType,i.InvoiceSymbol 

	DECLARE @InvoiceSymbol NVARCHAR(20) = ''
	DECLARE @InvoiceNumber INT = 1
	DECLARE @SameInvoiceNoList TABLE (InvoiceType INT)

	-- 1: software fee, 6: hosting fee
	IF @InvoiceType IN (1,6) INSERT INTO @SameInvoiceNoList VALUES(1),(6)
	-- 5: debit note, 10: debit note for return AMF
	ELSE IF @InvoiceType IN (5,10) INSERT INTO @SameInvoiceNoList VALUES(5),(10)
	-- others
	ELSE INSERT INTO @SameInvoiceNoList VALUES(@InvoiceType)

	SELECT	TOP 1 @InvoiceSymbol = i.InvoiceSymbol
	FROM	@InvoiceTmp i
	WHERE	i.InvoiceType IN (SELECT * FROM @SameInvoiceNoList)

	SELECT	@InvoiceNumber = ISNULL(MAX(i.InvoiceNumber), 0) + 1
	FROM	@InvoiceTmp i		
	WHERE	i.InvoiceSymbol = @InvoiceSymbol
	
	UPDATE	@InvoiceInfo
	SET		InvoiceSymbol = @InvoiceSymbol,
			InvoiceNumber = @InvoiceNumber,
			InvoiceLanguage = (SELECT TOP 1 d.InvoiceLanguage FROM dbo.OAS_PartyDetail d WHERE d.PartyID=@PayerId)
	
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
	FROM @InvoiceInfo ii

END
GO

/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceReferenceGet]
	@BillerId		INT,
	@PayerId 		INT,
	@InvTypeId		SMALLINT,
	@Environment	VARCHAR(10)
AS
/*	
	Created: 2017.07.19 - Scofield.Huynh [#79905]
	DB:		DBCUST.bodb_Licensee	

	Revisions:
		- 20180131@Bruce: support credit note for setup fee [#90274]
		- 20220418@Percy: Return InvoiceItemType & Amount [RedmineID: #164139]
*/
BEGIN
	DECLARE @InvoiceStatement TABLE (InvoiceHeaderId BIGINT, InvItemTypeId SMALLINT, Amount MONEY)
	INSERT INTO @InvoiceStatement (InvoiceHeaderId, InvItemTypeId, Amount)
	SELECT s.InvoiceHeaderId, s.InvItemTypeId, s.Amount
	FROM (
		SELECT InvoiceHeaderId
			,CASE
				WHEN @InvTypeId = 4 AND InvItemTypeId = 1 THEN 12 -- Credit Note for Software Fee
				WHEN @InvTypeId = 4 AND InvItemTypeId = 2 THEN 45 -- Credit Note for Setup Fee
				WHEN @InvTypeId = 4 AND InvItemTypeId = 3 THEN 46 -- Credit Note for AMF
				WHEN @InvTypeId = 4 AND InvItemTypeId = 6 THEN 14 -- Credit Note for Rebate
				WHEN @InvTypeId = 5 AND InvItemTypeId = 1 THEN 11 -- Debit Note for Software Fee
				WHEN @InvTypeId = 5 AND InvItemTypeId = 6 THEN 13 -- Debit Note for Rebate
				END AS InvItemTypeId
			,CASE WHEN InvItemTypeId IN (2, 3) THEN ISNULL(Income, 0) - ISNULL(Expense, 0) ELSE 0 END AS Amount
			,ROW_NUMBER() OVER(PARTITION BY InvoiceHeaderId, InvItemTypeId ORDER BY InvoiceStatementId) AS RN
		FROM dbo.LA_InvoiceStatement WITH (NOLOCK)
		WHERE RefPartyId = @PayerId
			AND InvItemTypeId IN (1, 2, 3, 6) -- Software Fee, Setup Fee, AMF, Rebate
			AND (@InvTypeId = 4 OR InvItemTypeId NOT IN (2, 3)) -- Don't get Setup Fee, AMF for Debit Note
	) s
	WHERE s.RN = 1

	;WITH CTE_InvoiceStatement AS (
		SELECT s1.InvoiceHeaderId
			,STUFF((
				SELECT N',{'
					+ N'"InvItemTypeId":' + CONVERT(NVARCHAR(10), s2.InvItemTypeId)
					+ N', "Amount":' + CONVERT(NVARCHAR(20), s2.Amount)
					+ N'}'
				FROM @InvoiceStatement s2
				WHERE s2.InvoiceHeaderId = s1.InvoiceHeaderId
				ORDER BY s2.InvItemTypeId
				FOR XML PATH('')), 1, 1, '') AS StatementJson
		FROM @InvoiceStatement s1
		GROUP BY s1.InvoiceHeaderId
	)
	SELECT
		h.OfficialInvoiceNo		AS InvoiceNo,
		h.InvoiceHeaderId		AS InvoiceId,
		h.InvoiceType,
		CONVERT(NVARCHAR(1000), N'[' + s.StatementJson + N']') AS StatementJson
	FROM dbo.LA_InvoiceHeader h WITH(NOLOCK)
		INNER JOIN CTE_InvoiceStatement s ON h.InvoiceHeaderId = s.InvoiceHeaderId
	WHERE h.InvoiceType IN (1, 3, 7) -- Software Fee, Rebate, Setup Fee
		AND h.StatusId = 0 -- normal
		AND h.PartyId = @PayerId 
		AND h.BillerId = @BillerId
		AND h.Environment = @Environment
	ORDER BY h.CreatedDateTime
END
GO
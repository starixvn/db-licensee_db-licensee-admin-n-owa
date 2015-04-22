USE bodb_licensee
GO
ALTER PROCEDURE dbo.LA_Discount_ValidatePayerAssignment @DiscountId INT
	, @PayerIdList VARCHAR(4000) = ''
	, @Mode VARCHAR(10) = 'R'

	, @ErrCode INT = 0 OUTPUT
	, @ErrMsg VARCHAR(4000)= '' OUTPUT
AS
/*  
	 Created: 20150422@Patrick
	 Task : Validate list of Payers have applied to billing Invoice yet
	 DB: DB052.bodb_Licensee
	 Revisions:     
		
	 Params:
		+ @Mode : 
			- R: Remove, A: Add
*/
BEGIN
	SET NOCOUNT ON
	RETURN --TODO: when implement Invoice page
	IF ISNULL(@PayerIdList , '') = '' OR ISNULL(@DiscountId, 0) = 0
		RETURN

	DECLARE @PayerNameList VARCHAR(4000), @DiscountType TINYINT
	
	--get discount group type
	SELECT @DiscountType = DiscountGroupType
	FROM dbo.LA_DiscountGroupHeader WITH(NOLOCK)
	WHERE DiscountGroupId = @DiscountId

	IF @Mode = 'R'
	BEGIN
		SET @PayerNameList = NULL

		SELECT COALESCE(@PayerNameList + ',' + '''' + CASE WHEN ISNULL(pp.BrandName, '') = '' THEN ISNULL(p.PartyName, '') ELSE ISNULL(pp.BrandName, '') END + ''''
						, '''' + CASE WHEN ISNULL(pp.BrandName, '') = '' THEN ISNULL(p.PartyName, '') ELSE ISNULL(pp.BrandName, '') END + '''')
		FROM dbo.LA_DiscountGroupAssignment a WITH(NOLOCK)
			INNER JOIN dbo.LA_DiscountGroupHeader h WITH(NOLOCK) ON a.DiscountGroupId = h.DiscountGroupId
			INNER JOIN dbo.OAS_Party p WITH(NOLOCK) ON a.PartyID = p.PartyID
			INNER JOIN dbo.OAS_PartyDetail pp WITH(NOLOCK) ON a.PartyID = pp.PartyID
			--INNER JOIN dbo.LA_InvoiceHeader inv WITH(NOLOCK) ON p.PartyId = inv.PartyId  --> todo
		WHERE h.DiscountGroupId = @DiscountId
			AND a.PartyId IN (SELECT val FROM strSplit(@PayerIdList, ','))
		IF ISNULL(@PayerNameList , '') = ''
		BEGIN
			SELECT @ErrMsg = CASE WHEN @DiscountType = 1 THEN 'Payer ' + @PayerNameList + ' cannot be removed out of the discount group, since the discount was applied for the payer to issue invoice!. 
If you want to stop the discount program for the Payer, please set To date of the discount to End then create new group for other Payers.'
							ELSE 'Payer '+ @PayerNameList +' cannot be removed out of the rebate group, since the rebate was applied for the payer to issue invoice!.
If you want to stop the rebate program for the Payer, please set To date of the rebate to End then create new group for other Payers.' END
				, @ErrCode = 512
			RETURN
		END
	END
	
END
GO
/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_Discount_ValidatePayerAssignment]
	@DiscountGroupId INT
	, @PayerIdList VARCHAR(4000) = ''
	, @Mode VARCHAR(10) = 'R'

	, @ErrCode INT = 0 OUTPUT
	, @ErrMsg VARCHAR(4000)= '' OUTPUT
AS
/*  
	 Created: 20150422@Patrick
	 Task: Validate list of Payers have applied to billing Invoice yet
	 DB: DB052.bodb_Licensee
	 
	 Revisions:
		- 20150422@Patrick: Initialize SP
		
	 Params:
		+ @Mode : 
			- R: Remove, A: Add
*/
BEGIN
	SET NOCOUNT ON
	--RETURN --TODO: when implement Invoice page
	IF ISNULL(@PayerIdList , '') = '' OR ISNULL(@DiscountGroupId, 0) = 0
		RETURN

	DECLARE @PayerNameList VARCHAR(4000), @DiscountType TINYINT
	
	--get discount group type
	SELECT @DiscountType = DiscountGroupType
	FROM dbo.LA_DiscountGroupHeader WITH(NOLOCK)
	WHERE DiscountGroupId = @DiscountGroupId
	IF @Mode = 'A'
	BEGIN
		IF EXISTS(SELECT 1 
				FROM dbo.LA_DiscountGroupHeader h WITH (NOLOCK)
					INNER JOIN dbo.LA_DiscountGroupAssignment a WITH (NOLOCK) ON h.DiscountGroupId = a.DiscountGroupId					
				WHERE h.DiscountGroupType = @DiscountType
					AND a.PartyId IN (SELECT val FROM strSplit(@PayerIdList, ','))
				 )				
	BEGIN
		DECLARE @tempDiscount AS TABLE (Indx INT IDENTITY(1,1),DiscountGroupId INT, DiscountType INT , FromDate DATE, ToDate DATE)

		INSERT INTO @tempDiscount (DiscountGroupId, DiscountType, FromDate, ToDate)
		SELECT h.DiscountGroupId, h.DiscountGroupType, FromDate, ToDate
		FROM dbo.LA_DiscountGroupHeader h WITH (NOLOCK)
			INNER JOIN dbo.LA_DiscountGroupAssignment a WITH (NOLOCK) ON h.DiscountGroupId = a.DiscountGroupId			
		WHERE h.DiscountGroupType = @DiscountType
			AND a.PartyId IN (SELECT val FROM strSplit(@PayerIdList, ','))
		UNION 
		SELECT DiscountGroupId, DiscountGroupType, FromDate, ToDate
		FROM dbo.LA_DiscountGroupHeader h WITH (NOLOCK)
		WHERE h.DiscountGroupId = @DiscountGroupId
		IF EXISTS (
			SELECT TOP 1 1
			FROM @tempDiscount a LEFT JOIN @tempDiscount b ON a.Indx != b.Indx  AND a.DiscountType = b.DiscountType
			WHERE  (a.FromDate BETWEEN b.FromDate AND b.ToDate
						OR a.ToDate BETWEEN b.FromDate AND b.ToDate
						OR b.FromDate BETWEEN a.FromDate AND a.ToDate
						OR b.ToDate BETWEEN a.FromDate AND a.ToDate
					))
		BEGIN			
			DECLARE @PartyName VARCHAR(8000)
			SELECT @PartyName = COALESCE(@PartyName + ',' + '''' + CASE WHEN ISNULL(pp.BrandName, '') = '' THEN ISNULL(p.PartyName, '') ELSE ISNULL(pp.BrandName, '') END + ''''
						, '''' + CASE WHEN ISNULL(pp.BrandName, '') = '' THEN ISNULL(p.PartyName, '') ELSE ISNULL(pp.BrandName, '') END + '''')
			FROM dbo.OAS_Party p WITH(NOLOCK) 
				INNER JOIN dbo.OAS_PartyDetail pp WITH(NOLOCK) ON p.PartyID = pp.PartyID				
			WHERE p.PartyId IN (SELECT val FROM strSplit(@PayerIdList, ','))
			SELECT @ErrMsg = 'Payer ' + @PartyName + ' which being applied other discount at the time, please check again!'
			, @ErrCode = 200
			RETURN
		END
	END
	END
	IF @Mode = 'R'
	BEGIN
		RETURN
		SET @PayerNameList = NULL		

		SELECT COALESCE(@PayerNameList + ',' + '''' + CASE WHEN ISNULL(pp.BrandName, '') = '' THEN ISNULL(p.PartyName, '') ELSE ISNULL(pp.BrandName, '') END + ''''
						, '''' + CASE WHEN ISNULL(pp.BrandName, '') = '' THEN ISNULL(p.PartyName, '') ELSE ISNULL(pp.BrandName, '') END + '''')
		FROM dbo.LA_DiscountGroupAssignment a WITH(NOLOCK)
			INNER JOIN dbo.LA_DiscountGroupHeader h WITH(NOLOCK) ON a.DiscountGroupId = h.DiscountGroupId
			INNER JOIN dbo.OAS_Party p WITH(NOLOCK) ON a.PartyID = p.PartyID
			INNER JOIN dbo.OAS_PartyDetail pp WITH(NOLOCK) ON a.PartyID = pp.PartyID
			--INNER JOIN dbo.LA_InvoiceHeader inv WITH(NOLOCK) ON p.PartyId = inv.PartyId  --> todo
		WHERE h.DiscountGroupId = @DiscountGroupId
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
/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/

CREATE PROCEDURE [dbo].[SH_SabaPlay_RebateIns] 
	@GroupName			NVARCHAR(50),
	@FromDate			DATE,
	@ToDate				DATE,
	@ProductIds			VARCHAR(512) = '',
	@PartyIds			VARCHAR(MAX) = '',
	@Rate				DECIMAL(9, 8),
	@RebateGroupType	TINYINT,
	@UserId				INT,
	@Remark				NVARCHAR(4000) = '',
	@LoginIp			VARCHAR (50)	= '',
	@ErrCode			INT = 0 OUTPUT,
	@ErrMsg				VARCHAR(4000)= '' OUTPUT,
	@GroupIdOut			INT = 0 OUTPUT,
	@CurrencyIds		VARCHAR(4000) = ''
AS
/*  
	 Created: 20251017@Danny [#241642]
	 Task : Manage Rebate On winloss group (SabaPlay)
	 DB: DBCUST.bodb_licensee   

	 Revisions:  
		- 20251017@Danny: Create SP [#241642]
*/

BEGIN
	SET NOCOUNT ON
	DECLARE @startRun DATETIME, @endRun DATETIME, @duration INT, @logSPData NVARCHAR(MAX), 
			@logSPDataOld	NVARCHAR(MAX), @actionID INT = 2400, @logSPData_inv NVARCHAR(MAX), @logSPDataOld_inv NVARCHAR(MAX)

	SET @startRun = GETDATE()

	--check empty
	IF ISNULL(@GroupName, '') = ''
	BEGIN
		SELECT @ErrCode = 501, @ErrMsg = 'Please fill out group name.'
		RETURN
	END

	--check exists
	IF EXISTS (SELECT 1 FROM dbo.LA_DiscountGroupHeader WITH(NOLOCK) WHERE DiscountGroupName = @GroupName AND DiscountGroupType = 52)
	BEGIN
		SELECT @ErrCode = 502, @ErrMsg = 'Group name exists. Please try again.'
		RETURN
	END

	DECLARE @Products TABLE (ProductId TINYINT)
	DECLARE @Payers TABLE (PayerId INT)
	DECLARE @Currencies TABLE (CurrencyId INT)

	--parse product rebate group
	IF @ProductIds = ''
	BEGIN
		SELECT @ErrCode = 503, @ErrMsg = 'Please select at least 1 product!'
		RETURN	
	END

	INSERT INTO @Products(ProductId)
	SELECT value FROM STRING_SPLIT(@ProductIds, ',')

	--parse assigned payer to group
	IF @PartyIds = ''
	BEGIN
		SELECT @ErrCode = 503, @ErrMsg = 'Please add at least one licensee.'
		RETURN	
	END

	INSERT INTO @Payers(PayerId)
	SELECT value FROM STRING_SPLIT(@PartyIds, ',')

	INSERT INTO @Currencies(CurrencyId)
	SELECT value FROM STRING_SPLIT(@CurrencyIds, ',')
	
	--check required fields
	IF @FromDate IS NULL OR @ToDate IS NULL
		OR @Rate < 0
	BEGIN
		SELECT @ErrMsg = 'Please fill all required field.', @ErrCode = 503
		RETURN
	END

	-- check exists setting
	BEGIN
		SELECT @ErrMsg = ''
		
		IF @RebateGroupType = 52 
		BEGIN
			IF EXISTS (
				SELECT TOP 1 1 
				FROM dbo.LA_DiscountGroupHeader h WITH (NOLOCK)
				INNER JOIN dbo.LA_DiscountGroupAssignment a WITH (NOLOCK) ON h.DiscountGroupId = a.DiscountGroupId
				INNER JOIN dbo.LA_DiscountGroupProduct p WITH (NOLOCK) ON p.DiscountGroupId = a.DiscountGroupId
				INNER JOIN @Payers t ON t.PayerId = a.PartyID
				INNER JOIN @Products pt ON pt.ProductId = p.ProductId
				WHERE h.DiscountGroupType = 52 AND h.FromDate <= @ToDate AND h.ToDate >= @FromDate
			)
			BEGIN
				SELECT @ErrCode = 503, @ErrMsg = 'Licensee is in another Rebate on Lic WL group.'
				RETURN
			END	
		END
	END

	-- if group is tier rebate, check base currency all payers
	DECLARE @BaseCurrencyId INT = 0

	-- #Region Insert 

	--insert rebate group header
	INSERT INTO dbo.LA_DiscountGroupHeader(DiscountGroupName, DiscountGroupType, CurrencyId, FromDate, ToDate, Remark, [Priority], ModifiedDate)
	VALUES(@GroupName, @RebateGroupType, @BaseCurrencyId, @FromDate, @ToDate, @Remark, 2, GETDATE())

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Insert failed. Please try again.', @ErrCode = 503
		RETURN
	END

	SET @GroupIdOut = SCOPE_IDENTITY()
	IF ISNULL(@GroupIdOut, 0) = 0
	BEGIN
		SELECT @ErrMsg = 'Insert failed. Please try again.', @ErrCode = 503
		RETURN
	END

	--insert rebate group detail
	INSERT INTO dbo.LA_DiscountGroupDetail(DiscountGroupId, FromAmount, ToAmount, Rate)
	Values(@GroupIdOut, 0, 0, @Rate)

	IF @@ERROR <> 0
	BEGIN
		DELETE dbo.LA_DiscountGroupHeader WITH(ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
		SELECT @ErrMsg = 'Insert failed. Please try again.', @ErrCode = 503
		RETURN
	END

	--insert rebate group product
	INSERT INTO dbo.LA_DiscountGroupProduct(DiscountGroupId, ProductId, CalculationType)
	SELECT DISTINCT @GroupIdOut, ProductId, 0
	FROM @Products

	IF @@ERROR <> 0
	BEGIN
		DELETE dbo.LA_DiscountGroupHeader WITH(ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
		DELETE dbo.LA_DiscountGroupDetail WITH(ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
		SELECT @ErrMsg = 'Insert failed. Please try again.', @ErrCode = 503
		RETURN
	END

	--insert rebate group assignment
	INSERT INTO dbo.LA_DiscountGroupAssignment(DiscountGroupId, PartyID, IsApplyDiscount)
	SELECT DISTINCT @GroupIdOut, PayerId, 0
	FROM @Payers

	IF @@ERROR <> 0
	BEGIN
		DELETE dbo.LA_DiscountGroupHeader WITH(ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
		DELETE dbo.LA_DiscountGroupDetail WITH(ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
		DELETE dbo.LA_DiscountGroupProduct WITH(ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
		SELECT @ErrMsg = 'Insert failed. Please try again.', @ErrCode = 503
		RETURN
	END

	-- #Endregion Insert 

	--write log
	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)
	
	SELECT @logSPData = (
		SELECT  ld.DiscountGroupName 'gs.gn', 
				FORMAT (ld.FromDate,'MMM dd, yyyy') 'gs.af', 
				FORMAT (ld.ToDate,'MMM dd, yyyy') 'gs.at',
				CAST (ldg.Rate * 100 AS VARCHAR(50)) + ' %' 'gs.r' ,
				'Rebate on Licensing WL' 'gs.rt',
				ld.Remark 'gs.rm',
				pig.val AS 'gs.pig',
				pig.pid AS 'gs.pid',
				pa.val AS 'gs.pa'
		FROM LA_DiscountGroupHeader ld WITH(NOLOCK) 
		INNER JOIN LA_DiscountGroupDetail ldg WITH(NOLOCK) ON ld.DiscountGroupId = ldg.DiscountGroupId
		CROSS APPLY (
			SELECT  STRING_AGG(op.PartyName,', ') AS val, STRING_AGG(CAST(lda.PartyID AS VARCHAR(50)),',') AS pid
			FROM	LA_DiscountGroupAssignment lda
			INNER JOIN	OAS_Party op WITH(NOLOCK) ON   lda.PartyID = op.PartyID
			WHERE lda.DiscountGroupId = ld.DiscountGroupId
		) pig
		CROSS APPLY 
		(
			SELECT STRING_AGG(p3.ProductName,', ') AS val
			FROM  LA_DiscountGroupProduct ldp WITH(NOLOCK)
			INNER JOIN vw_SabaPlay_Products p3 ON ldp.ProductId = p3.Productid
			WHERE ld.DiscountGroupId = ldp.DiscountGroupId
		) pa
	
		WHERE ld.DiscountGroupId = @GroupIdOut
		FOR JSON PATH, WITHOUT_ARRAY_WRAPPER 
	)

	-- Write Log
	EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIp
		,@SPName		= 'SH_SabaPlay_RebateIns'
		,@CustId		= @GroupIdOut
		,@Duration		= @duration
		,@TrackingValue2 = @LogSPData
		,@TrackingValue = @LogSPDataOld
		,@ActionID		 = @actionID

	BEGIN
		 -- LA_InvoiceSetting
		 DROP TABLE IF EXISTS #tmp_LA_InvoiceSetting
		 CREATE TABLE #tmp_LA_InvoiceSetting (
			FromPartyId INT, 
			ToPartyId	INT, 
			InvTempId	SMALLINT, 
			BankId		TINYINT, 
			ProductId	TINYINT, 
			ActiveAddress TINYINT,
			InvTypeId	SMALLINT
		)

		INSERT INTO #tmp_LA_InvoiceSetting (FromPartyId,	ToPartyId,	ProductId,	InvTypeId,	InvTempId,	BankId,	ActiveAddress)
		SELECT DISTINCT ld.PartyID, x.ToPartyId, NULL, 3, x.InvTempId, x.BankId, CASE WHEN opd.Address2 IS NOT NULL THEN 2 ELSE 1 END ActiveAdress
		FROM	LA_DiscountGroupAssignment ld WITH(NOLOCK)
		INNER JOIN OAS_PartyDetail opd WITH(NOLOCK) ON ld.PartyID = opd.PartyID
		LEFT JOIN LA_InvoiceSetting lis WITH(NOLOCK) ON ld.PartyID = lis.FromPartyId AND lis.InvTypeId = 3 -- Rebate
		CROSS APPLY (
		SELECT DISTINCT lis1.ToPartyId, lis1.InvTempId, lis1.BankId
		FROM LA_InvoiceSetting lis1 WITH(NOLOCK) WHERE ld.PartyID = lis1.FromPartyId AND lis1.InvTypeId = 1 -- Software Data & Licensing Fees
		) x
		WHERE	ld.DiscountGroupId = @GroupIdOut AND lis.FromPartyId IS NULL

		DECLARE @PartyID INT

		WHILE EXISTS (SELECT TOP 1 1 FROM #tmp_LA_InvoiceSetting )
		BEGIN
			SELECT TOP 1 @PartyID = FromPartyId FROM #tmp_LA_InvoiceSetting 

			--build old log
			; WITH items AS
				(
				SELECT  op.PartyName,od.BrandName,iv.BillerName,iv.bank,iv.InvTypeName,iv.InvTemplateName,iv.ActiveAddress,iv.ProductIDs,iv.InvTypeId, iv.FakeID
				FROM	OAS_Party op WITH(NOLOCK)
				INNER JOIN OAS_PartyDetail od WITH(NOLOCK) ON od.PartyID = op.PartyID
				OUTER APPLY (
					SELECT b.BillerName
							,lt.InvTypeName
							,temp.InvTemplateName
							,CASE WHEN li.BankId > 0 THEN 'Bank ' + CAST(li.BankId AS VARCHAR(3)) ELSE '' END Bank
								,CASE WHEN li.ActiveAddress = 1 THEN od.Address1
									WHEN li.ActiveAddress = 2 THEN od.Address2 END ActiveAddress
							,STRING_AGG(p.ProductName,', ') ProductIDs
							,lt.InvTypeId
							,li.ToPartyId FakeID
					FROM LA_InvoiceSetting li WITH(NOLOCK) 
					LEFT JOIN LA_InvoiceType lt with(nolock) ON li.InvTypeID  = lt.InvTypeID
					LEFT JOIN dbo.LA_BillerInfo b WITH (NOLOCK) ON li.ToPartyId = b.PartyId
					LEFT JOIN dbo.LA_InvoiceTemplate temp WITH (NOLOCK) ON li.InvTempId = temp.InvTemplateId
					LEFT JOIN vw_SabaPlay_Products p WITH (NOLOCK) ON li.ProductId = p.Productid
					WHERE li.FromPartyId = op.PartyID
					GROUP BY b.BillerName, lt.InvTypeName, CASE WHEN li.BankId > 0 THEN 'Bank ' + CAST(li.BankId AS VARCHAR(3)) ELSE '' END
						, temp.InvTemplateName ,li.ActiveAddress
						,CASE WHEN li.ActiveAddress = 1 THEN od.Address1
							WHEN li.ActiveAddress = 2 THEN od.Address2 END, lt.InvTypeId
						,li.ToPartyId
				) iv
				WHERE op.PartyID =@PartyID
			), i AS
			(
				SELECT i.PartyName, i.BrandName, i.BillerName, i.Bank, i.FakeID
				FROM items i
				GROUP BY i.PartyName, i.BrandName, i.BillerName, i.Bank, i.FakeID
			),log_detail AS
			(
			SELECT i.FakeID, i.PartyName, i.BrandName, i.BillerName, i.Bank 
					,i1.InvTypeName it1, i1.InvTemplateName itn1, i1.ActiveAddress ad1, i1.ProductIDs p1
					,i3.InvTypeName it3, i3.InvTemplateName itn3, i3.ActiveAddress ad3
					,i4.InvTypeName it4, i4.InvTemplateName itn4, i4.ActiveAddress ad4
					,i5.InvTypeName it5, i5.InvTemplateName itn5, i5.ActiveAddress ad5
					,i6.InvTypeName it6, i6.InvTemplateName itn6, i6.ActiveAddress ad6
					,i7.InvTypeName it7, i7.InvTemplateName itn7, i7.ActiveAddress ad7
					,i10.InvTypeName it10, i10.InvTemplateName itn10, i10.ActiveAddress ad10
					,i11.InvTypeName it11, i11.InvTemplateName itn11, i11.ActiveAddress ad11
					,i12.InvTypeName it12, i12.InvTemplateName itn12, i12.ActiveAddress ad12
					,ISNULL(i1.InvTypeId,0) + ISNULL(i3.InvTypeId,0) + ISNULL(i4.InvTypeId,0) + ISNULL(i5.InvTypeId,0) + ISNULL(i6 .InvTypeId,0) + ISNULL(i7.InvTypeId,0)
						+ ISNULL(i11.InvTypeId,0) + ISNULL(i12.InvTypeId,0) AS istotal

			FROM  i
			LEFT JOIN items i1 ON i1.PartyName = i.PartyName AND ISNULL(i1.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i1.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i1.Bank,'') = ISNULL(i.Bank,'') AND i1.InvTypeId = 1 
			LEFT JOIN items i3 ON i3.PartyName = i.PartyName AND ISNULL(i3.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i3.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i3.Bank,'') = ISNULL(i.Bank,'') AND i3.InvTypeId = 3 
			LEFT JOIN items i4 ON i4.PartyName = i.PartyName AND ISNULL(i4.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i4.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i4.Bank,'') = ISNULL(i.Bank,'') AND i4.InvTypeId = 4 
			LEFT JOIN items i5 ON i5.PartyName = i.PartyName AND ISNULL(i5.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i5.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i5.Bank,'') = ISNULL(i.Bank,'') AND i5.InvTypeId = 5 
			LEFT JOIN items i6 ON i6.PartyName = i.PartyName AND ISNULL(i6.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i6.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i6.Bank,'') = ISNULL(i.Bank,'') AND i6.InvTypeId = 6 
			LEFT JOIN items i7 ON i7.PartyName = i.PartyName AND ISNULL(i7.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i7.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i7.Bank,'') = ISNULL(i.Bank,'') AND i7.InvTypeId = 7
			LEFT JOIN items i10 ON i10.PartyName = i.PartyName AND ISNULL(i10.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i10.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i10.Bank,'') = ISNULL(i.Bank,'') AND i10.InvTypeId = 10 
			LEFT JOIN items i11 ON i11.PartyName = i.PartyName AND ISNULL(i11.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i11.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i11.Bank,'') = ISNULL(i.Bank,'') AND i11.InvTypeId = 11 
			LEFT JOIN items i12 ON i12.PartyName = i.PartyName AND ISNULL(i12.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i12.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i12.Bank,'') = ISNULL(i.Bank,'') AND i12.InvTypeId = 12  
			)SELECT @logSPDataOld_inv = 
			(
				SELECT  l.PartyName as 'pi.pn', l.BrandName AS 'pi.bn' , x.x AS 'bl'
				FROM log_detail l
				OUTER APPLY 
				(
					SELECT 
					( 
						SELECT u.FakeID ,u.BillerName AS bln, u.Bank AS b, 
							u.it1, u.itn1, u.ad1, u.p1
							,u.it3, u.itn3, u.ad3
							,u.it4, u.itn4, u.ad4
							,u.it5, u.itn5, u.ad5
							,u.it6, u.itn6, u.ad6
							,u.it7, u.itn7, u.ad7
							,u.it10, u.itn10, u.ad10
							,u.it11, u.itn11, u.ad11
							,u.it12, u.itn12, u.ad12
						FROM log_detail u 
						WHERE u.PartyName = l.PartyName AND ISNULL(u.BrandName,'') = ISNULL(l.BrandName,'')  AND l.istotal > 0
						FOR JSON PATH
					)x
				) x
				GROUP BY l.PartyName, l.BrandName , x.x FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
			)
		
			INSERT INTO LA_InvoiceSetting (FromPartyId,	ToPartyId,	ProductId,	InvTypeId,	InvTempId,	BankId,	ActiveAddress)
			SELECT FromPartyId,	ToPartyId,	ProductId,	InvTypeId,	InvTempId,	BankId,	ActiveAddress 
			FROM #tmp_LA_InvoiceSetting WHERE FromPartyId = @PartyID

			IF @@ERROR <> 0
			BEGIN
				SELECT @ErrMsg = 'Update failed. Please try again.', @ErrCode = 504
				RETURN
			END

			; WITH items AS
			(
				SELECT  op.PartyName,od.BrandName,iv.BillerName,iv.bank,iv.InvTypeName,iv.InvTemplateName,iv.ActiveAddress,iv.ProductIDs,iv.InvTypeId, iv.FakeID
				FROM	OAS_Party op WITH(NOLOCK)
				INNER JOIN OAS_PartyDetail od WITH(NOLOCK) ON od.PartyID = op.PartyID
				OUTER APPLY (
					SELECT b.BillerName
							,lt.InvTypeName
							,temp.InvTemplateName
							,CASE WHEN li.BankId > 0 THEN 'Bank ' + CAST(li.BankId AS VARCHAR(3)) ELSE '' END Bank
								,CASE WHEN li.ActiveAddress = 1 THEN od.Address1
									WHEN li.ActiveAddress = 2 THEN od.Address2 END ActiveAddress
							,STRING_AGG(p.ProductName,', ') ProductIDs
							,lt.InvTypeId
							,li.ToPartyId AS FakeID
					FROM LA_InvoiceSetting li WITH(NOLOCK) 
					LEFT JOIN LA_InvoiceType lt with(nolock) ON li.InvTypeID  = lt.InvTypeID
					LEFT JOIN dbo.LA_BillerInfo b WITH (NOLOCK) ON li.ToPartyId = b.PartyId
					LEFT JOIN dbo.LA_InvoiceTemplate temp WITH (NOLOCK) ON li.InvTempId = temp.InvTemplateId
					LEFT JOIN vw_SabaPlay_Products p WITH (NOLOCK) ON li.ProductId = p.Productid
					WHERE li.FromPartyId = op.PartyID
					GROUP BY b.BillerName, lt.InvTypeName, CASE WHEN li.BankId > 0 THEN 'Bank ' + CAST(li.BankId AS VARCHAR(3)) ELSE '' END
						, temp.InvTemplateName ,li.ActiveAddress
						,CASE WHEN li.ActiveAddress = 1 THEN od.Address1
							WHEN li.ActiveAddress = 2 THEN od.Address2 END, lt.InvTypeId
						,li.ToPartyId
				) iv
				WHERE op.PartyID =@PartyID
			), i AS
			(
				SELECT i.PartyName, i.BrandName, i.BillerName, i.Bank, i.FakeID
				FROM items i
				GROUP BY i.PartyName, i.BrandName, i.BillerName, i.Bank, i.FakeID
			),log_detail AS
			(
			SELECT i.FakeID, i.PartyName, i.BrandName, i.BillerName, i.Bank 
					,i1.InvTypeName it1, i1.InvTemplateName itn1, i1.ActiveAddress ad1, i1.ProductIDs p1
					,i3.InvTypeName it3, i3.InvTemplateName itn3, i3.ActiveAddress ad3
					,i4.InvTypeName it4, i4.InvTemplateName itn4, i4.ActiveAddress ad4
					,i5.InvTypeName it5, i5.InvTemplateName itn5, i5.ActiveAddress ad5
					,i6.InvTypeName it6, i6.InvTemplateName itn6, i6.ActiveAddress ad6
					,i7.InvTypeName it7, i7.InvTemplateName itn7, i7.ActiveAddress ad7
					,i10.InvTypeName it10, i10.InvTemplateName itn10, i10.ActiveAddress ad10
					,i11.InvTypeName it11, i11.InvTemplateName itn11, i11.ActiveAddress ad11
					,i12.InvTypeName it12, i12.InvTemplateName itn12, i12.ActiveAddress ad12
					,ISNULL(i1.InvTypeId,0) + ISNULL(i3.InvTypeId,0) + ISNULL(i4.InvTypeId,0) + ISNULL(i5.InvTypeId,0) + ISNULL(i6 .InvTypeId,0) + ISNULL(i7.InvTypeId,0)
						+ ISNULL(i11.InvTypeId,0) + ISNULL(i12.InvTypeId,0) AS istotal

			FROM  i
			LEFT JOIN items i1 ON i1.PartyName = i.PartyName AND ISNULL(i1.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i1.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i1.Bank,'') = ISNULL(i.Bank,'') AND i1.InvTypeId = 1 
			LEFT JOIN items i3 ON i3.PartyName = i.PartyName AND ISNULL(i3.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i3.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i3.Bank,'') = ISNULL(i.Bank,'') AND i3.InvTypeId = 3 
			LEFT JOIN items i4 ON i4.PartyName = i.PartyName AND ISNULL(i4.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i4.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i4.Bank,'') = ISNULL(i.Bank,'') AND i4.InvTypeId = 4 
			LEFT JOIN items i5 ON i5.PartyName = i.PartyName AND ISNULL(i5.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i5.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i5.Bank,'') = ISNULL(i.Bank,'') AND i5.InvTypeId = 5 
			LEFT JOIN items i6 ON i6.PartyName = i.PartyName AND ISNULL(i6.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i6.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i6.Bank,'') = ISNULL(i.Bank,'') AND i6.InvTypeId = 6 
			LEFT JOIN items i7 ON i7.PartyName = i.PartyName AND ISNULL(i7.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i7.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i7.Bank,'') = ISNULL(i.Bank,'') AND i7.InvTypeId = 7
			LEFT JOIN items i10 ON i10.PartyName = i.PartyName AND ISNULL(i10.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i10.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i10.Bank,'') = ISNULL(i.Bank,'') AND i10.InvTypeId = 10 
			LEFT JOIN items i11 ON i11.PartyName = i.PartyName AND ISNULL(i11.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i11.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i11.Bank,'') = ISNULL(i.Bank,'') AND i11.InvTypeId = 11 
			LEFT JOIN items i12 ON i12.PartyName = i.PartyName AND ISNULL(i12.BrandName,'') = ISNULL(i.BrandName,'') AND  ISNULL(i12.BillerName,'')  = ISNULL(i.BillerName,'') AND ISNULL(i12.Bank,'') = ISNULL(i.Bank,'') AND i12.InvTypeId = 12 
			)SELECT @logSPData_inv = 
			(
				SELECT  l.PartyName as 'pi.pn', l.BrandName AS 'pi.bn' , x.x AS 'bl'
				FROM log_detail l
				OUTER APPLY 
				(
					SELECT 
					( 
						SELECT u.FakeID ,u.BillerName AS bln, u.Bank AS b, 
							u.it1, u.itn1, u.ad1, u.p1
							,u.it3, u.itn3, u.ad3
							,u.it4, u.itn4, u.ad4
							,u.it5, u.itn5, u.ad5
							,u.it6, u.itn6, u.ad6
							,u.it7, u.itn7, u.ad7
							,u.it10, u.itn10, u.ad10
							,u.it11, u.itn11, u.ad11
							,u.it12, u.itn12, u.ad12
						FROM log_detail u 
						WHERE u.PartyName = l.PartyName AND ISNULL(u.BrandName,'') = ISNULL(l.BrandName,'')   AND l.istotal > 0
						FOR JSON PATH
					)x
				) x
				GROUP BY l.PartyName, l.BrandName , x.x FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
			)

			-- Write Log
			EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
				@UserId			= @UserID
				,@IP			= @LoginIP
				,@SPName		= 'SH_SabaPlay_RebateIns'
				,@CustId		= @PartyID
				,@Duration		= @duration
				,@TrackingValue2 = @logSPData_inv
				,@TrackingValue =  @logSPDataOld_inv
				,@ActionID		= 1003


			 DELETE FROM #tmp_LA_InvoiceSetting WHERE FromPartyId = @PartyID
		END
	END
END
GO

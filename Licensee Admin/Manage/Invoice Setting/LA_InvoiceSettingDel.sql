/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_Licensee
GO

ALTER PROCEDURE [dbo].[LA_InvoiceSettingDel] 
	@BillerID				INT				
	, @PayerID				INT					
	, @UserID				INT
	, @LoginIP				VARCHAR (50)	= ''
	, @ErrCode				INT				= 0		OUTPUT
	, @ErrMsg				NVARCHAR(1000)	= ''	OUTPUT
AS
/*  
	 Created: 20150414@Florent
	 Task : Biller Delete Payer setting
	 DB: DBCUST.bodb_Licensee
   
	 Revisions:
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]
		- 20230310@Danny: Insert new log with more information [#FeatureID 175125]

	 Params:
		+ @InvoiceSettingXML: '<InvoiceSettings>
									<InvoiceSetting>
										<InvoiceTypeId>1</InvoiceTypeId>  
										<InvoiceTemplateId>1</InvoiceTemplateId>
										<ProductIds ProductId = "1"></ProductIds>
										<ProductIds ProductId = "3"></ProductIds>
										<ProductIds ProductId = "5"></ProductIds>
									</InvoiceSetting>
							
									<InvoiceSetting>
										<InvoiceTypeId>2</InvoiceTypeId>  
										<InvoiceTemplateId>1</InvoiceTemplateId>
										<ProductIds />
									</InvoiceSetting>
							
									<InvoiceSetting>
										<InvoiceTypeId>3</InvoiceTypeId>  
										<InvoiceTemplateId>3</InvoiceTemplateId>
										<ProductIds />
									</InvoiceSetting>
								</InvoiceSettings>'	
*/
BEGIN
	SET NOCOUNT ON
	IF ISNULL(@PayerID, '') = '' OR ISNULL(@BillerID, '') = ''
		RETURN
-- For writing log
	DECLARE 
		@startRun		DATETIME,
		@endRun			DATETIME,
		@duration		INT,
		@logSPData		NVARCHAR(MAX),
		@logSPDataOld	NVARCHAR(MAX)

	-- Time start
	SET @startRun = GETDATE()	
	
	IF EXISTS (SELECT 1 
					FROM dbo.LA_InvoiceSetting i WITH (NOLOCK) 						
					WHERE i.FromPartyId = @PayerID AND i.ToPartyId = @BillerID)	
	BEGIN		
		--write log
		; WITH Items AS 
			(
				SELECT		op.PartyName
							,od.BrandName
							,b.BillerName
							,lt.InvTypeName
							,CASE WHEN li.BankId > 0 THEN 'Bank ' + CAST(li.BankId AS VARCHAR(3)) ELSE '' END Bank
							,temp.InvTemplateName
							, CASE WHEN li.ActiveAddress = 1 THEN od.Address1
									WHEN li.ActiveAddress = 2 THEN od.Address2 END ActiveAddress
							,STRING_AGG(CASE WHEN li.ProductID = 0 THEN 'Sportsbook' ELSE p.ProductName END,',') ProductIDs
				FROM  OAS_Party op WITH(NOLOCK)
				INNER JOIN OAS_PartyDetail od WITH(NOLOCK) ON od.PartyID = op.PartyID
				LEFT JOIN  LA_InvoiceSetting li with(nolock)  ON li.FromPartyId = op.PartyID AND li.FromPartyID =@PayerID AND li.ToPartyId = @BillerID
				LEFT JOIN LA_InvoiceType lt with(nolock) ON li.InvTypeID  = lt.InvTypeID
				LEFT JOIN dbo.LA_BillerInfo b WITH (NOLOCK) ON li.ToPartyId = b.PartyId
				LEFT JOIN dbo.LA_InvoiceTemplate temp WITH (NOLOCK) ON li.InvTempId = temp.InvTemplateId
				LEFT JOIN Product3rd p WITH (NOLOCK) ON li.ProductId = p.Productid
				WHERE op.PartyID =@PayerID 
				GROUP BY op.PartyName, od.BrandName, b.BillerName, lt.InvTypeName, CASE WHEN li.BankId > 0 THEN 'Bank ' + CAST(li.BankId AS VARCHAR(3)) ELSE '' END
						, temp.InvTemplateName ,li.ActiveAddress
						,CASE WHEN li.ActiveAddress = 1 THEN od.Address1
							WHEN li.ActiveAddress = 2 THEN od.Address2 END
			), ItemsDetail AS
			(
				SELECT t.PartyName,t.BrandName, t.BillerName, t.Bank, x.iv
				FROM Items t
				OUTER APPLY (
					SELECT 
					(
						SELECT InvTypeName AS it,  InvTemplateName AS itn , ActiveAddress AS ad,  ProductIDs  AS p
						FROM Items u
						WHERE  t.PartyName = u.PartyName AND t.BrandName = u.BrandName AND t.BillerName = u.BillerName AND  t.Bank = u.Bank
						FOR JSON PATH, INCLUDE_NULL_VALUES 
					) AS iv
				) x
				GROUP BY  t.PartyName,t.BrandName, t.BillerName, t.Bank, x.iv
			) SELECT @logSPDataOld = 
				(   
					SELECT t.PartyName as 'pi.pn', t.BrandName AS 'pi.bn' , x.x AS 'bl'
					FROM ItemsDetail t
					OUTER APPLY 
					(
						SELECT
						(
							SELECT u.BillerName AS bln, u.Bank AS b, JSON_QUERY(u.iv) iv
							FROM ItemsDetail u 
							WHERE u.PartyName = t.PartyName AND u.BrandName = t.BrandName
							FOR JSON PATH, INCLUDE_NULL_VALUES 
						) x
					) x
					GROUP BY t.PartyName, t.BrandName, x.x 
					FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES 
				)

		--delete statement
		DELETE FROM dbo.LA_InvoiceSetting WITH (ROWLOCK, UPDLOCK)				
			WHERE FromPartyId = @PayerID 
				AND ToPartyId = @BillerId

		IF @@error <> 0
		BEGIN
			SELECT 	@ErrMsg = 'Delete failed. Please try again.', @ErrCode = 140	
			RETURN
		END

		; WITH Items AS 
		(
			SELECT		op.PartyName
						,od.BrandName
						,b.BillerName
						,lt.InvTypeName
						,CASE WHEN li.BankId > 0 THEN 'Bank ' + CAST(li.BankId AS VARCHAR(3)) ELSE '' END Bank
						,temp.InvTemplateName
						, CASE WHEN li.ActiveAddress = 1 THEN od.Address1
								WHEN li.ActiveAddress = 2 THEN od.Address2 END ActiveAddress
						,STRING_AGG(CASE WHEN li.ProductID = 0 THEN 'Sportsbook' ELSE p.ProductName END,',') ProductIDs
			FROM  OAS_Party op WITH(NOLOCK)
			INNER JOIN OAS_PartyDetail od WITH(NOLOCK) ON od.PartyID = op.PartyID
			LEFT JOIN  LA_InvoiceSetting li with(nolock)  ON li.FromPartyId = op.PartyID AND li.FromPartyID =@PayerID AND li.ToPartyId = @BillerID
			LEFT JOIN LA_InvoiceType lt with(nolock) ON li.InvTypeID  = lt.InvTypeID
			LEFT JOIN dbo.LA_BillerInfo b WITH (NOLOCK) ON li.ToPartyId = b.PartyId
			LEFT JOIN dbo.LA_InvoiceTemplate temp WITH (NOLOCK) ON li.InvTempId = temp.InvTemplateId
			LEFT JOIN Product3rd p WITH (NOLOCK) ON li.ProductId = p.Productid
			WHERE op.PartyID =@PayerID 
			GROUP BY op.PartyName, od.BrandName, b.BillerName, lt.InvTypeName, CASE WHEN li.BankId > 0 THEN 'Bank ' + CAST(li.BankId AS VARCHAR(3)) ELSE '' END
					, temp.InvTemplateName ,li.ActiveAddress
					,CASE WHEN li.ActiveAddress = 1 THEN od.Address1
						WHEN li.ActiveAddress = 2 THEN od.Address2 END
		), ItemsDetail AS
		(
			SELECT t.PartyName,t.BrandName, t.BillerName, t.Bank, x.iv
			FROM Items t
			OUTER APPLY (
				SELECT 
				(
					SELECT InvTypeName AS it,  InvTemplateName AS itn , ActiveAddress AS ad,  ProductIDs  AS p
					FROM Items u
					WHERE  t.PartyName = u.PartyName AND t.BrandName = u.BrandName AND t.BillerName = u.BillerName AND  t.Bank = u.Bank
					FOR JSON PATH, INCLUDE_NULL_VALUES 
				) AS iv
			) x
			GROUP BY  t.PartyName,t.BrandName, t.BillerName, t.Bank, x.iv
		) SELECT @logSPData = 
			(   
				SELECT t.PartyName as 'pi.pn', t.BrandName AS 'pi.bn' , x.x AS 'bl'
				FROM ItemsDetail t
				OUTER APPLY 
				(
					SELECT
					(
						SELECT u.BillerName AS bln, u.Bank AS b, JSON_QUERY(u.iv) iv
						FROM ItemsDetail u 
						WHERE u.PartyName = t.PartyName AND u.BrandName = t.BrandName
						FOR JSON PATH, INCLUDE_NULL_VALUES 
					) x
				) x
				GROUP BY t.PartyName, t.BrandName, x.x 
				FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES 
			)

		SET @endRun = GETDATE()
		SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 
	END

	-- Write Log
	EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIP
		,@SPName		= 'LA_InvoiceSettingDel'
		,@CustId		= @PayerID
		,@Duration		= @duration
		,@TrackingValue2 = @logSPData
		,@TrackingValue =  @logSPDataOld
		,@ActionID		= 1004
END
GO
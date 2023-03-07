/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_DiscountDel] 
	@DiscountGroupId INT, 
	@ErrCode INT = 0 OUTPUT, 
	@ErrMsg VARCHAR(4000) = '' OUTPUT,
	@UserID	INT,
	@LoginIP VARCHAR (50)	= ''
AS
/*  
	 Created: 20180705@Parsons [#94282]
	 Task: Enhance Manage Discount group function to support more discount schemes
	 DB: DBCUST.bodb_licensee   

	 Revisions:  
		- 20180705@Parsons: Delete discount groups [#94282]
		- 20211101@Percy: Remove useless params [RedmineID: #162158]
		- 20230403@Danny: Insert new log with more information [#FeatureID 175125]
	 
	 Params:

	 Explannation: 
*/

BEGIN
	SET NOCOUNT ON
	DECLARE @logDiscountOld NVARCHAR(MAX), @logDiscount NVARCHAR(MAX), @logDiscountActionID INT = 1602 -- delete
	DECLARE @startRun DATETIME, @endRun	DATETIME, @duration INT

	SET @startRun = GETDATE()
	BEGIN TRY
		-- Log data
		SELECT @logDiscountOld = (
				SELECT ld.DiscountGroupName 'gr.gn', 
					  e.Code AS  'gr.e', 
					  ld.FromDate AS 'gr.af', 
					  ld.ToDate AS 'gr.at', 
					  STRING_AGG(CASE WHEN ldp.ProductId = 0 THEN 'Sportsbook' ELSE p3.ProductName END  ,',') 'gr.p',
					  l.l AS 'll',
					  ds.s AS 'ds'
				FROM LA_DiscountGroupHeader ld with(nolock) 
				INNER JOIN CUSTDB.dbo.Exchange e  with(nolock) ON ld.CurrencyId = e.ExchangeId
				INNER JOIN LA_DiscountGroupProduct ldp WITH(NOLOCK) ON ld.DiscountGroupId = ldp.DiscountGroupId 
				LEFT JOIN Product3rd p3 WITH(NOLOCK) ON ldp.ProductId = p3.Productid

				OUTER APPLY 
				(
					SELECT (
						SELECT  PartyID AS 'l.pi',LicenseeName 'l.ln', Remark 'l.rm', 
						STRING_AGG(CASE WHEN CountInPer = 1 THEN Curr ELSE '' END  ,',') 'l.cip',
						STRING_AGG(CASE WHEN AppliedDiscount = 1 THEN Curr ELSE '' END  ,',')'l.ap'
						FROM 
							(
								select  op.PartyID as PartyID ,op.PartyName AS LicenseeName, CASE WHEN lgc.CurrencyId = 142 THEN 'USDT' 
													 WHEN lgc.CurrencyId IN (96, 202) THEN e.Code + ' ('+ e.currency+ ')'
													 ELSE e.Code END AS Curr,
	  
										CASE WHEN lgc.CalculationType IN (1,3) THEN 1 ELSE 0 END CountInPer,
										CASE WHEN lgc.CalculationType IN (2,3) THEN 1 ELSE 0 END AppliedDiscount,
										lga.Remark
								FROM LA_DiscountGroupAssignment lga WITH(NOLOCK)
								INNER JOIN LA_DiscountGroupCurrency  lgc WITH(NOLOCK) ON lga.PartyID = lgc.PartyID AND lga.DiscountGroupId = lgc.DiscountGroupId
								INNER JOIN OAS_Party op WITH(NOLOCK) ON lga.PartyID = op.PartyID
								INNER JOIN CUSTDB.dbo.Exchange e  with(nolock) ON lgc.CurrencyId = e.ExchangeId
								WHERE lga.DiscountGroupId = ld.DiscountGroupId
							) x  GROUP BY PartyID, LicenseeName, Remark FOR JSON PATH
					 )l
				) l
				OUTER APPLY 
				(	
					SELECT 
					(
						SELECT FromAmount 'st.wlf', ToAmount 'st.wlt', ChargeRateAfterDiscount 'st.cr'
						FROM LA_DiscountGroupDetail  ldg WITH(NOLOCK) 
						WHERE ldg.DiscountGroupId = ld.DiscountGroupId FOR JSON PATH
					) s
				) ds
				WHERE ld.DiscountGroupID = @DiscountGroupID
				GROUP BY ld.DiscountGroupName, e.Code, ld.FromDate, ld.ToDate, l.l, ds.s
				 FOR JSON PATH,  WITHOUT_ARRAY_WRAPPER 
		 )
		DELETE dbo.LA_DiscountGroupAssignment WITH(ROWLOCK) WHERE DiscountGroupId = @DiscountGroupId --remove assignment
		DELETE dbo.LA_DiscountGroupProduct WITH(ROWLOCK) WHERE DiscountGroupId = @DiscountGroupId --remove product
		DELETE dbo.LA_DiscountGroupCurrency WITH(ROWLOCK) WHERE DiscountGroupId = @DiscountGroupId --remove currency
		DELETE dbo.LA_DiscountGroupDetail WITH(ROWLOCK) WHERE DiscountGroupId = @DiscountGroupId --remove detail
		DELETE dbo.LA_DiscountGroupHeader WITH(ROWLOCK) WHERE DiscountGroupId = @DiscountGroupId --remove header

	END TRY
	BEGIN CATCH
		SELECT @ErrMsg = 'Delete failed. Please try again.', @ErrCode = 516
		RETURN
	END CATCH

	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 
	EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
			@UserId			= @UserID
			,@IP			= @LoginIP
			,@SPName		= 'LA_DiscountDel'
			,@CustId		= @DiscountGroupID
			,@Duration		= @duration
			,@TrackingValue2 = @logDiscount
			,@TrackingValue = @logDiscountOld
			,@ActionID		 = @logDiscountActionID
END
GO

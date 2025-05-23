import { ListDashes } from "@phosphor-icons/react/dist/ssr/ListDashes";
import { Badge } from "@pythnetwork/component-library/Badge";
import { Breadcrumbs } from "@pythnetwork/component-library/Breadcrumbs";
import { Button } from "@pythnetwork/component-library/Button";
import { Drawer, DrawerTrigger } from "@pythnetwork/component-library/Drawer";
import { StatCard } from "@pythnetwork/component-library/StatCard";
import { notFound } from "next/navigation";
import type { ReactNode } from "react";

import styles from "./layout.module.scss";
import { PriceFeedSelect } from "./price-feed-select";
import { ReferenceData } from "./reference-data";
import { Cluster, getFeeds } from "../../services/pyth";
import { Cards } from "../Cards";
import { Explain } from "../Explain";
import { FeedKey } from "../FeedKey";
import {
  LivePrice,
  LiveConfidence,
  LiveLastUpdated,
  LiveValue,
} from "../LivePrices";
import {
  YesterdaysPricesProvider,
  PriceFeedChangePercent,
} from "../PriceFeedChangePercent";
import { PriceFeedTag } from "../PriceFeedTag";
import { PriceName } from "../PriceName";
import { TabPanel, TabRoot, Tabs } from "../Tabs";

type Props = {
  children: ReactNode;
  params: Promise<{
    slug: string;
  }>;
};

export const PriceFeedLayout = async ({ children, params }: Props) => {
  const [{ slug }, feeds] = await Promise.all([
    params,
    getFeeds(Cluster.Pythnet),
  ]);
  const symbol = decodeURIComponent(slug);
  const feed = feeds.find((item) => item.symbol === symbol);

  return feed ? (
    <div className={styles.priceFeedLayout}>
      <section className={styles.header}>
        <div className={styles.headerRow}>
          <Breadcrumbs
            label="Breadcrumbs"
            items={[
              { href: "/", label: "Home" },
              { href: "/price-feeds", label: "Price Feeds" },
              { label: feed.product.display_symbol },
            ]}
          />
          <div>
            <Badge variant="neutral" style="outline" size="md">
              {feed.product.asset_type.toUpperCase()}
            </Badge>
          </div>
        </div>
        <div className={styles.headerRow}>
          <PriceFeedSelect className={styles.priceFeedSelect}>
            <PriceFeedTag symbol={feed.symbol} />
          </PriceFeedSelect>
          <PriceFeedTag className={styles.priceFeedTag} symbol={feed.symbol} />
          <div className={styles.rightGroup}>
            <FeedKey
              className={styles.feedKey ?? ""}
              feedKey={feed.product.price_account}
            />
            <DrawerTrigger>
              <Button variant="outline" size="sm" beforeIcon={ListDashes}>
                Reference Data
              </Button>
              <Drawer fill title="Reference Data">
                <ReferenceData
                  feed={{
                    symbol: feed.symbol,
                    feedKey: feed.product.price_account,
                    assetClass: feed.product.asset_type,
                    base: feed.product.base,
                    description: feed.product.description,
                    country: feed.product.country,
                    quoteCurrency: feed.product.quote_currency,
                    tenor: feed.product.tenor,
                    cmsSymbol: feed.product.cms_symbol,
                    cqsSymbol: feed.product.cqs_symbol,
                    nasdaqSymbol: feed.product.nasdaq_symbol,
                    genericSymbol: feed.product.generic_symbol,
                    weeklySchedule: feed.product.weekly_schedule,
                    schedule: feed.product.schedule,
                    contractId: feed.product.contract_id,
                    displaySymbol: feed.product.display_symbol,
                    exponent: feed.price.exponent,
                    numComponentPrices: feed.price.numComponentPrices,
                    numQuoters: feed.price.numQuoters,
                    minPublishers: feed.price.minPublishers,
                    lastSlot: feed.price.lastSlot,
                    validSlot: feed.price.validSlot,
                  }}
                />
              </Drawer>
            </DrawerTrigger>
          </div>
        </div>
        <Cards>
          <StatCard
            variant="primary"
            header={
              <>
                Aggregated <PriceName assetClass={feed.product.asset_type} />
              </>
            }
            stat={
              <LivePrice
                feedKey={feed.product.price_account}
                cluster={Cluster.Pythnet}
              />
            }
          />
          <StatCard
            header="Confidence"
            stat={
              <LiveConfidence
                feedKey={feed.product.price_account}
                cluster={Cluster.Pythnet}
              />
            }
            corner={
              <Explain size="xs" title="Confidence">
                <p>
                  <b>Confidence</b> is how far from the aggregate price Pyth
                  believes the true price might be. It reflects a combination of
                  the confidence of individual quoters and how well individual
                  quoters agree with each other.
                </p>
                <Button
                  size="xs"
                  variant="solid"
                  href="https://docs.pyth.network/price-feeds/best-practices#confidence-intervals"
                  target="_blank"
                >
                  Learn more
                </Button>
              </Explain>
            }
          />
          <StatCard
            header={
              <>
                1-Day <PriceName assetClass={feed.product.asset_type} /> Change
              </>
            }
            stat={
              <YesterdaysPricesProvider
                feeds={{ [feed.symbol]: feed.product.price_account }}
              >
                <PriceFeedChangePercent feedKey={feed.product.price_account} />
              </YesterdaysPricesProvider>
            }
          />
          <StatCard
            header="Last Updated"
            stat={
              <LiveLastUpdated
                feedKey={feed.product.price_account}
                cluster={Cluster.Pythnet}
              />
            }
          />
        </Cards>
      </section>
      <TabRoot>
        <Tabs
          label="Price Feed Navigation"
          prefix={`/price-feeds/${slug}`}
          items={[
            { segment: undefined, children: "Chart" },
            {
              segment: "publishers",
              children: (
                <div className={styles.priceComponentsTabLabel}>
                  <span>Publishers</span>
                  <Badge size="xs" style="filled" variant="neutral">
                    <LiveValue
                      feedKey={feed.product.price_account}
                      field="numComponentPrices"
                      defaultValue={feed.price.numComponentPrices}
                      cluster={Cluster.Pythnet}
                    />
                  </Badge>
                </div>
              ),
            },
          ]}
        />
        <TabPanel className={styles.body ?? ""}>{children}</TabPanel>
      </TabRoot>
    </div>
  ) : (
    notFound()
  );
};
